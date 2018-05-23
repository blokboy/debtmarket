pragma solidity ^0.4.18;

import "./DebtRegistry.sol";
import "./DebtToken.sol";
import "./CDOTermsContract.sol";
import "./RepaymentRouter.sol";
import "./AssetCollateralizer.sol";
import "./TokenTransferProxy.sol";

/**
 * The CDO contract encompasses the business logic of a two tranched CDO containing an arbitrary amount of 
 * CollateralAgreements (loans). The contract allows a user to create a CDO derived from a collection of 
 * CollateralAgreements (loans), combining the payouts of the loans, and distributing said funds to holders
 * of the NFT tokens linked to the CDO. The contract also implements functions for allowing users to purchase 
 * NFT tokens for a particular CDO as well.
 *
 * Author: Jordan Marsaw -- Github: blokboy
 */

contract CDO {
	
	DebtRegistry debtRegistry;
	bytes32 termsContractParameters;

	// Represent the tranche membership by assignment of DebtTokens for tranche
	DebtToken seniorToken; 
	DebtToken mezzanineToken;
	
	CDOTermsContract cdoTerms;
	RepaymentRouter repaymentRouter;
	AssetCollateralizer assetCollateralizer;
	CollateralAgreement CDO;

	mapping (bytes32 => CollateralAgreement) agreementIdToCA;
	mapping (uint => CollateralAgreement) tokenIdToCA;

	// Using the uint[] array to keep track of tokenIds and address to track users connected to ID.
	uint[] seniors;
	uint[] mezzanine;
	address[] mezzanineAddress;
	address[] seniorAddress;
	uint expectedPayoutTotal;
	uint avgLockUpTime;

	// Price of an NFT token for particular CDO specified by the owner of the CDO in constructor.
	uint seniorPrice; 
	uint mezzaninePrice;


	/**
     * Constructor that sets up CDO as well as contract connections.
     */

	function CDO (
		address debtRegistryAddress,
		address _cdoTermsContractAddress,
		address _repaymentRouterAddress,
		address assetCollateralizerAddress,
		address tokenTransferProxyAddress,
		uint _seniorPrice,
		uint _mezzaninePrice,
		CollateralAgreement[] _CA
	) 	internal
	{
		require(_CA.length > 0);
		address repaymentRouterAddress = _repaymentRouterAddress;
		address cdoTermsContractAddress = _cdoTermsContractAddress;
		debtRegistry = DebtRegistry(debtRegistryAddress);
		seniorToken = DebtToken(debtRegistryAddress);
		mezzanineToken = DebtToken(debtRegistryAddress);
		cdoTerms = CDOTermsContract(cdoTermsContractAddress);
		repaymentRouter = RepaymentRouter(debtRegistryAddress, tokenTransferProxyAddress);
		assetCollateralizer = AssetCollateralizer(assetCollateralizerAddress);
		seniorPrice = _seniorPrice;
		mezzaninePrice = _mezzaninePrice;
		CDO = packageAgreements(_CA);
		( , termsContractParameters) = debtRegistry.getTerms(CDO.debtAgreementId);
    
	}

   /**
     * Function to combine all the components of individual CollateralAgreements into one CollateralAgreement.
     * The idea is to create a solution that will allow for a more scalable start to implementing a CDO; however,
     * the use of arrays will eventually lead to a gas limit once it becomes too large, so this solution still isn't 
     * good enough when you're talking about having the capability to synthesize multiple CollateralAgreements. 
     * The debtAgreementId for the CDO will be an iterative hash of the debtAgreement, along with the next debtAgreementId
     * to give users the ability to derive the CDO's debtAgreementId hash from the chronological order of the Collateral
     * Agreements in the array. Similar ideas for lockUpPeriodEnd & EPV.
     */

	function packageAgreements(CollateralAgreement[] _CA) internal returns (CollateralAgreement) 
	{
		assetCollateralizer.CollateralAgreement _CDO = assetCollateralizer.CollateralAgreement({
			debtAgreementId: bytes32(0),
			owner: address(0),
			lockupPeriodEnd: uint(0)
		});

		uint expectedPayoutValue = 0;

		for(uint i = 0; i < _CA.length; i++) {
			_CDO.debtAgreementId = keccak256(_cdo.debtAgreementId, _CA[i].debtAgreementId);
			_CDO.lockupPeriodEnd = _cdo.lockupPeriodEnd + _CA[i].lockupPeriodEnd;
			expectedPayoutValue = expectedPayoutValue + CDOTerms.getExpectedRepaymentValue(
								  _CA[i].debtAgreementId, TermsParameters, block.number);
		}

		avgLockUpTime = uint(_CDO.lockupPeriodEnd / _CA.length);
		expectedPayoutTotal = expectedPayoutValue;
		_CDO.owner = msg.sender;

		require(avgLockUpTime > now);
		require(expectedPayoutTotal > 0);
		require(_CDO.owner != address(0));

		agreementIdToCA[_CDO.debtAgreementId] = _CDO;

		return _CDO;
	}

   /**
     * Function to check for expected awards based on ExpectedPaymentTotal
     */

	function getPayouts(uint EPT) returns (uint, uint) {
		require(EPT > 0);
		uint seniorAward = (1 * EPT * 60) / 100;
		uint mezzanineAward = EPT - seniorAward;

		return (seniorAward, mezzanineAward);
	}

   /**
     * Function to allow investors to purchase NFT tokens connected to this CDO.
     */

	function buySeniorNFT(bytes32 _debtAgreementId) payable internal {
		require(_debtAgreementId != bytes32(0));
		require(msg.sender != address(0));
		require(msg.sender != agreementIdToCA[_debtAgreementId].owner);
		require(seniors.length >= 0);
		require(seniors.length < 6);
		require(msg.value >= seniorPrice);

		uint seniorNFT = seniorToken.create(repaymentRouterAddress, msg.sender, agreementIdToCA[_debtAgreementId].owner,
											agreementIdToCA[_debtAgreementId], 1, cdoTermsContractAdress, 
											assetCollateralizer.termsContractParameters, 1);

		seniorAddress.push(msg.sender);
		seniors.push(seniorNFT);
		tokenIdToCA[seniorNFT] = agreementIdToCA[_debtAgreementId];
		seniorToken._setTokenOwner(seniorNFT, msg.sender);
		tokenIdToCA[seniorNFT].owner.transfer(msg.value);
	}
 
   /**
     * Function to allow investors to purchase NFT tokens connected to this CDO.
     */

	function buyMezzanineNFT(bytes32 _debtAgreementId) payable internal {
		require(_debtAgreementId != bytes32(0));
		require(msg.sender != address(0));
		require(msg.sender != agreementIdToCA[_debtAgreementId].owner);
		require(mezzanine.length >= 0);
		require(mezzanine.length < 4);
		require(msg.value >= mezzaninePrice);

		uint mezzanineNFT = mezzanineToken.create(repaymentRouterAddress, msg.sender, agreementIdToCA[_debtAgreementId].owner, 
											      agreementIdToCA[_debtAgreementId], 1, cdoTermsContractAdress, 
											      assetCollateralizer.termsContractParameters, 1);
		mezzanineAddress.push(msg.sender);
		mezzanine.push(mezzanineNFT);
		tokenIdToCA[mezzanineNFT] = CDO;
		mezzanineToken._setTokenOwner(mezzanineNFT, msg.sender);
		CDO.owner.transfer(msg.value);
	}

   /**
     * Function to handle the distribution of payments to particular tranche NFT holders.
     */

	function payOutTranches(bytes32 _debtAgreementId) private payable {
		require(msg.sender == agreementIdToCA[_debtAgreementId].owner);
		require(avgLockUpTime > uint(now)); // If the LockUpTime has already passed, then REVERT.
			uint seniorValue = 1;
			uint mezzanineValue = 1;
			if(msg.value >= expectedPayoutTotal) { // If the payment is enough to cover the debts
				
				(seniorValue, mezzanineValue) = getPayouts(expectedPayoutTotal);
				
				if(seniors.length > 0) { // Are there any senior holders to payout?
					
					seniorValue = uint(seniorValue / seniors.length);
					for(uint i = seniors.length - 1; i >= 0; i--) {
						delete tokenIdToCA[seniors[i]];
						assetCollateralizer.withdrawCollateral(seniors[i]);
						seniorAddress[i].transfer(seniorValue);
					}
			
					del seniors; // Clear up the space for the array upon complete payOut
				} else {
					
					seniorValue = uint(0);
				}
				
				if(mezzanine.length > 0) {
				
					mezzanineValue = uint(mezzanineValue / mezzanine.length);
					for(uint i = mezzanine.length - 1; i >= 0; i--) {
						delete tokenIdToCA[mezzanine[i]];
						assetCollateralizer.withdrawCollateral(mezzanine[i]);
						mezzanineAddress[i].transfer(mezzanineValue);
					}
					
					del mezzanine;
				} else {
					mezzanineValue = uint(0);
				}
				
			  } else { // if msg.value < expectedPayoutTotal still give what's available and update balances
				
			        (seniorValue, mezzanineValue) = getPayouts(uint(msg.value));
				if(seniors.length > 0) {
					seniorValue = uint(seniorValue / seniors.length);
					for(uint i = seniors.length - 1; i >= 0; i--) {
						seniorAddress[i].transfer(seniorValue);
					}
				} else {
					seniorValue = uint(0);
				}
				if(mezzanine.length > 0) {
					mezzanineValue = uint(mezzanineValue / mezzanine.length);
					for(uint i = mezzanine.length - 1; i >= 0; i--) {
						mezzanineAddress[i].transfer(mezzanineValue );
					}
				} else {
					mezzanineValue = uint(0);
				}

				expectedPayoutTotal = expectedPayoutTotal - (seniorValue + mezzanineValue);
			}
		
	}

}