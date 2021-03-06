import {BigNumber} from "bignumber.js";
import {Dharma} from "dharma.js";

import * as ABIDecoder from "abi-decoder";
import * as chai from "chai";
import * as _ from "lodash";
import * as moment from "moment";
import * as Web3 from "web3";
import * as Units from "./test_utils/units";
import * as utils from "./test_utils/utils";

import {DebtKernelContract} from "../../types/generated/debt_kernel";
import {DebtRegistryContract} from "../../types/generated/debt_registry";
import {DebtTokenContract} from "../../types/generated/debt_token";
import {DummyTokenContract} from "../../types/generated/dummy_token";
import {DummyTokenRegistryContract} from "../../types/generated/dummy_token_registry";
import {RepaymentRouterContract} from "../../types/generated/repayment_router";
import {TokenTransferProxyContract} from "../../types/generated/token_transfer_proxy";
import {CDO} from "../../types/generated/cdo";
import {CDOTermsContract} from "../../types/generated/cdo_terms_contract";

import {DebtKernelErrorCodes} from "../../types/errors";
import {DebtOrder, SignedDebtOrder} from "../../types/kernel/debt_order";

import {BigNumberSetup} from "./test_utils/bignumber_setup";
import ChaiSetup from "./test_utils/chai_setup";
import {INVALID_OPCODE, REVERT_ERROR} from "./test_utils/constants";

import {DebtOrderFactory} from "./factories/debt_order_factory";

import {TxDataPayable} from "../../types/common";

import leftPad = require("left-pad");

// Configure BigNumber exponentiation
BigNumberSetup.configure();

// Set up Chai
ChaiSetup.configure();
const expect = chai.expect;

const cdoTermsContract = artifacts.require("CDOTermsContract");
const dharma = new Dharma(web3);

contract("CDO", async (ACCOUNTS) => {
    let repaymentRouter: RepaymentRouterContract;
    let kernel: DebtKernelContract;
    let debtToken: DebtTokenContract;
    let principalToken: DummyTokenContract;
    let termsContract: CDOTermsContractContract;
    let tokenTransferProxy: TokenTransferProxyContract;

    let orderFactory: DebtOrderFactory;

    const CONTRACT_OWNER = ACCOUNTS[0];

    const DEBTOR_1 = ACCOUNTS[1];
    const DEBTOR_2 = ACCOUNTS[2];
    const DEBTOR_3 = ACCOUNTS[3];
    const DEBTORS = [
        DEBTOR_1,
        DEBTOR_2,
        DEBTOR_3,
    ];

    const CREDITOR_1 = ACCOUNTS[4];
    const CREDITOR_2 = ACCOUNTS[5];
    const CREDITOR_3 = ACCOUNTS[6];
    const CREDITORS = [
        CREDITOR_1,
        CREDITOR_2,
        CREDITOR_3,
    ];

    const PAYER = ACCOUNTS[7];

    const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

    const TX_DEFAULTS = { from: CONTRACT_OWNER, gas: 4000000 };

    before(async () => {
        const dummyTokenRegistryContract = await DummyTokenRegistryContract.deployed(web3, TX_DEFAULTS);
        const dummyREPTokenAddress = await dummyTokenRegistryContract.getTokenAddress.callAsync("REP");

        principalToken = await DummyTokenContract.at(dummyREPTokenAddress, web3, TX_DEFAULTS);

        kernel = await DebtKernelContract.deployed(web3, TX_DEFAULTS);
        debtToken = await DebtTokenContract.deployed(web3, TX_DEFAULTS);
        tokenTransferProxy = await TokenTransferProxyContract.deployed(web3, TX_DEFAULTS);

        await principalToken.setBalance.sendTransactionAsync(CREDITOR_1, Units.ether(100));
        await principalToken.setBalance.sendTransactionAsync(CREDITOR_2, Units.ether(100));
        await principalToken.setBalance.sendTransactionAsync(CREDITOR_3, Units.ether(100));

        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: DEBTOR_1 });
        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: DEBTOR_2 });
        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: DEBTOR_3 });

        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: CREDITOR_1 });
        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: CREDITOR_2 });
        await principalToken.approve.sendTransactionAsync(tokenTransferProxy.address,
            Units.ether(100), { from: CREDITOR_3 });

        const debtRegistry = await DebtRegistryContract.deployed(web3, TX_DEFAULTS);
        repaymentRouter = await RepaymentRouterContract.deployed(web3, TX_DEFAULTS);

        const termsContractTruffle = await CDOTermsContract.new(
            debtRegistry.address,
            principalToken.address,
            repaymentRouter.address,
        );

        // The typings we use ingest vanilla Web3 contracts, so we convert the
        // contract instance deployed by truffle into a Web3 contract instance
        const termsContractWeb3Contract =
            web3.eth.contract(CDOTermsContract.abi).at(termsContractTruffle.address);

        termsContract = new CDOTermsContractContract(termsContractWeb3Contract, TX_DEFAULTS);

        await tokenTransferProxy.addAuthorizedTransferAgent.sendTransactionAsync(repaymentRouter.address);

        const termLengthInBlocks = 43200;
        const principalPlusInterest = Units.ether(termsContract.getExpectedRepaymentValue());

        const uint16PrincipalPlusInterest = leftPad(web3.toHex(principalPlusInterest).substr(2), 32, "0");
        const uint16TermLength = leftPad(web3.toHex(termLengthInBlocks).substr(2), 32, "0");

        const termsContractParameters = "0x" + uint16PrincipalPlusInterest + uint16TermLength;

        const defaultOrderParams = {
            creditorFee: Units.ether(0),
            debtKernelContract: kernel.address,
            debtOrderVersion: kernel.address,
            debtTokenContract: debtToken.address,
            debtor: DEBTOR_1,
            debtorFee: Units.ether(0),
            expirationTimestampInSec: new BigNumber(moment().add(1, "days").unix()),
            issuanceVersion: repaymentRouter.address,
            orderSignatories: { debtor: DEBTOR_1, creditor: CREDITOR_1 },
            principalAmount: Units.ether(1),
            principalTokenAddress: principalToken.address,
            relayer: NULL_ADDRESS,
            relayerFee: Units.ether(0),
            termsContract: termsContract.address,
            termsContractParameters,
            underwriter: NULL_ADDRESS,
            underwriterFee: Units.ether(0),
            underwriterRiskRating: Units.percent(0),
        };

        orderFactory = new DebtOrderFactory(defaultOrderParams);

        ABIDecoder.addABI(repaymentRouter.abi);
    });

    after(() => {
        ABIDecoder.removeABI(repaymentRouter.abi);
    });

    describe("Example Tests", () => {
        let signedDebtOrder: SignedDebtOrder;
        let agreementId: string;
        let receipt: Web3.TransactionReceipt;

        before(async () => {
            // NOTE: For purposes of this assignment, we hard code a default principal + interest amount of 1.1 ether
            // If you're interested in how to vary this amount, poke around in the setup code above :)
            signedDebtOrder = await orderFactory.generateDebtOrder({
                creditor: CREDITOR_2,
                debtor: DEBTOR_2,
                orderSignatories: { debtor: DEBTOR_2, creditor: CREDITOR_2 },
            });

            // The unique id we use to refer to the debt agreement is the hash of its associated issuance commitment.
            agreementId = signedDebtOrder.getIssuanceCommitment().getHash();

            // Creditor fills the signed debt order, creating a debt agreement with a unique associated debt token
            const txHash = await kernel.fillDebtOrder.sendTransactionAsync(
                signedDebtOrder.getCreditor(),
                signedDebtOrder.getOrderAddresses(),
                signedDebtOrder.getOrderValues(),
                signedDebtOrder.getOrderBytes32(),
                signedDebtOrder.getSignaturesV(),
                signedDebtOrder.getSignaturesR(),
                signedDebtOrder.getSignaturesS(),
            );

            receipt = await web3.eth.getTransactionReceipt(txHash);
        });

        it('should deploy CDO contract', () => {
            return CDO.deployed().then((instance) => {
                return instance
            })
        })
        it('returns the CDO', () => {
            return CDO.deployed().then((instance) => {
                return instance.CDO.call()
                    .then((CDO) => {
                        return CDO
                    })
            })
        })
        it('returns the expected payout total', () => {
            return CDO.deployed().then((instance) => {
                return instance.expectedPayoutTotal.call()
                    .then((expectedPayoutTotal) => {
                       return expectedPayoutTotal
                    })
            })
        })
        it('returns the average lockup time', () => {
         return CDO.deployed().then((instance) => {
             return instance.avgLockupTime.call()
                    .then((avgLockupTime) => {
                        return avgLockupTime
                    })
            })
        })

        it("should issue creditor a unique debt token", async () => {
            await expect(debtToken.ownerOf.callAsync(new BigNumber(agreementId)))
                .to.eventually.equal(CREDITOR_2);
        });

        it("should allow debtor to make repayment", async () => {
            const creditorBalanceBefore = await principalToken.balanceOf.callAsync(CREDITOR_2);

            await repaymentRouter.repay.sendTransactionAsync(
                agreementId,
                Units.ether(1), // amount
                principalToken.address, // token type
                { from: DEBTOR_2 },
            );

            await expect(principalToken.balanceOf.callAsync(CREDITOR_2))
                .to.eventually.bignumber.equal(creditorBalanceBefore.plus(Units.ether(1)));
        });

        it("should allow creditor to transfer debt token to different address", async () => {
            await debtToken.transfer.sendTransactionAsync(
                CREDITOR_1, // to
                new BigNumber(agreementId), // tokenId
                { from: CREDITOR_2 },
            );

            await expect(debtToken.ownerOf.callAsync(new BigNumber(agreementId)))
                .to.eventually.equal(CREDITOR_1);
        });
    });
});
