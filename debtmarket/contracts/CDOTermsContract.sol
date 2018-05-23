//Derived from the SimpleInterestTermsContract from dharma

pragma solidity 0.4.18;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "./DebtRegistry.sol";
import "./TermsContract.sol";


contract CDOTermsContract is TermsContract {
    using SafeMath for uint;

    mapping (bytes32 => uint) valueRepaid;
    uint[] valueRepaidID; //Store the tokenIds of coins that have been paid back

    DebtRegistry debtRegistry;
    address repaymentTokenAddress;
    address repaymentRouterAddress;

    function SimpleInterestTermsContract(
        address _debtRegistryAddress,
        address _repaymentTokenAddress,
        address _repaymentRouterAddress
    )
        public
    {
        debtRegistry = DebtRegistry(_debtRegistryAdress);

        repaymentTokenAddress = _repaymentTokenAddress;
        repaymentRouterAddress = _repaymentRouterAddress;
    }

     /// When called, the registerRepayment function records the debtor's
     ///  repayment, as well as any auxiliary metadata needed by the contract
     ///  to determine ex post facto the value repaid (e.g. current USD
     ///  exchange rate)
     /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
     /// @param  payer address. The address of the payer.
     /// @param  beneficiary address. The address of the payment's beneficiary.
     /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
     /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    function registerRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    )
        public
        returns (bool _success)
    {
        if (msg.sender != repaymentRouter) {
            return false;
        }

        if (tokenAddress == repaymentToken) {
            valueRepaid[agreementId] = valueRepaid[agreementId].add(unitsOfRepayment);
        }

        return true;
    }

     /// A variant of the registerRepayment function that records the debtor's
     /// repayment in non-fungible tokens (i.e. ERC721), as well as any auxiliary metadata needed by the contract
     /// to determine ex post facto the value repaid (e.g. current USD
     /// exchange rate)
     /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
     /// @param  payer address. The address of the payer.
     /// @param  beneficiary address. The address of the payment's beneficiary.
     /// @param  tokenId The tokenId of the NFT transferred in the repayment transaction
     /// @param  tokenAddress The address of the token with which the repayment transaction was executed.
    function registerNFTRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 tokenId,
        address tokenAddress
    ) public 
      returns (bool _success)
    {
         if (msg.sender != repaymentRouterAddress) {
            return false;
        }

        if (tokenAddress == repaymentTokenAddress) {
            valueRepaidID.push(tokenId);
        }

        return true;
    }

     /// Returns the cumulative units-of-value expected to be repaid by any given blockNumber.
     ///  Note this is not a constant function -- this value can vary on basis of any number of
     ///  conditions (e.g. interest rates can be renegotiated if repayments are delinquent).
     /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
     /// @param  blockNumber uint. The block number for which repayment expectation is being queried.
     /// @return uint256 The cumulative units-of-value expected to be repaid by the time the given blockNumber lapses.
    function getExpectedRepaymentValue(
        bytes32 agreementId,
        uint256 blockNumber
    )
        public
        view
        returns (uint _expectedRepaymentValue)
    {
        bytes32 parameters = debtRegistry.getTermsContractParameters(agreementId);

        var (principalPlusInterest, termLengthInBlocks) = unpackParameters(parameters);

        if (debtRegistry.getIssuanceBlockNumber(agreementId).add(termLengthInBlocks) < blockNumber) {
            return principalPlusInterest;
        } else {
            return 0;
        }
    }

     /// Returns the cumulative units-of-value repaid by the point at which a given blockNumber has lapsed.
     /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
     /// @param blockNumber uint. The block number for which repayment value is being queried.
     /// @return uint256 The cumulative units-of-value repaid by the time the given blockNumber lapsed.
    function getValueRepaid(
        bytes32 agreementId,
        uint256 blockNumber
    )
        public
        view
        returns (uint _valueRepaid)
    {
        return valueRepaid[agreementId];
    }

    function unpackParameters(bytes32 parameters)
        public
        pure
        returns (uint128 _principalPlusInterest, uint128 _termLengthInBlocks)
    {
        bytes16[2] memory values = [bytes16(0), 0];

        assembly {
            mstore(values, parameters)
            mstore(add(values, 16), parameters)
        }

        return ( uint128(values[0]), uint128(values[1]) );
    }
}