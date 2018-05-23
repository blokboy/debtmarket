pragma solidity ^0.4.18;
import "https://github.com/dharmaprotocol/NonFungibleToken/blob/master/contracts/NonFungibleToken.sol";
import "./CDOTermsContract.sol";

contract AssetCollateralizer {
    NonFungibleToken assetContract; 
    CDOTermsContract termsContract;

    struct CollateralAgreement {
        bytes32 debtAgreementId;
        address owner;
        uint lockupPeriodEnd;
    }

    mapping (uint => CollateralAgreement) assetToCollateralAgreement;
    mapping (bytes32 => CollateralAgreement) debtIdToCollateralAgreement;

    function AssetCollateralizer(
        address assetContractAddress,
        address termsContractAddress
    ) 
    public
    {
        assetContract = NonFungibleToken(assetContractAddress);
        termsContract = CDOTermsContract(termsContractAddress);
    }

    function collateralize(bytes32 debtAgreementId, uint assetId, uint lockupPeriodEnd) {
        require(assetToCollateralAgreement[assetId].owner == address(0));
        require(lockupPeriodEnd > block.number);

        assetContract.transferFrom(msg.sender, this, assetId);

        assetToCollateralAgreement[assetId] = CollateralAgreement({
            debtAgreementId: debtAgreementId,
            owner: msg.sender,
            lockupPeriodEnd: lockupPeriodEnd
        });
    }

    function withdrawCollateral(uint assetId) {
        CollateralAgreement collateralAgreement = assetToCollateralAgreement[assetId];

        require(collateralAgreement.debtAgreementId != bytes32(0));

        address creditor = debtRegistry.getCreditor(collateralAgreement.debtAgreementId);
        

        CDOTermsContract termsContract = CDOTermsContract(termsContractAddress);

        uint expectedValueRepaid = termsContract.getExpectedRepaymentValue(collateralAgreement.debtAgreementId,
            termsContractParameters, block.number);
        uint actualValueRepaid = termsContract.getValueRepaid(collateralAgreement.debtAgreementId);

         if (actualValueRepaid < expectedValueRepaid) {
            releaseAsset(creditor, assetId);
        } else if (block.number > collateralAgreement.lockupPeriodEnd) {
            releaseAsset(collateralAgreement.owner, assetId);
        }

    }

    function releaseAsset(address to, uint assetId) internal {
        assetContract.transfer(to, assetId);
        assetToCollateralAgreement[assetId] = CollateralAgreement({
            debtAgreementId: bytes32(0),
            owner: address(0),
            lockupPeriodEnd: 0
        });
    }
}
