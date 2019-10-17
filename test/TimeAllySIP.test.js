/*
  Author: Soham Zemse (https://github.com/zemse)

  In this file you should write tests for your smart contract as you progress in developing your smart contract. For reference of Mocha testing framework, you can check out https://devdocs.io/mocha/.
*/

/// @dev importing packages required
const assert = require('assert');
const ethers = require('ethers');
const ganache = require('ganache-cli');

/// @dev initialising development blockchain
const provider = new ethers.providers.Web3Provider(ganache.provider({ gasLimit: 8000000 }));

/// @dev importing build file
const esJson = require('../build/Eraswap_EraswapToken.json');
const timeallySIPJSON = require('../build/TimeAllySIP_TimeAllySIP.json');

/// @dev initialize global variables
let accounts, esInstance, timeallySIPInstance;

/// @dev this is a test case collection
describe('Ganache Setup', async() => {

  /// @dev this is a test case. You first fetch the present state, and compare it with an expectation. If it satisfies the expectation, then test case passes else an error is thrown.
  it('initiates ganache and generates a bunch of demo accounts', async() => {

    /// @dev for example in this test case we are fetching accounts array.
    accounts = await provider.listAccounts();

    /// @dev then we have our expection that accounts array should be at least having 1 accounts
    assert.ok(accounts.length >= 1, 'atleast 2 accounts should be present in the array');
  });
});

describe('Eraswap Setup', () => {
  it('deploys Eraswap ERC20 contract from first account', async() => {

    /// @dev you create a contract factory for deploying contract. Refer to ethers.js documentation at https://docs.ethers.io/ethers.js/html/
    const EraswapContractFactory = new ethers.ContractFactory(
      esJson.abi,
      esJson.evm.bytecode.object,
      provider.getSigner(accounts[0])
    );
    esInstance =  await EraswapContractFactory.deploy();

    assert.ok(esInstance.address, 'conract address should be present');
  });
});

/// @dev this is another test case collection
describe('TimeAllySIP Contract', () => {

  /// @dev describe under another describe is a sub test case collection
  describe('TimeAllySIP Setup', async() => {

    /// @dev this is first test case of this collection
    it('deploys TimeAllySIP contract from first account with Eraswap contract address', async() => {

      /// @dev you create a contract factory for deploying contract. Refer to ethers.js documentation at https://docs.ethers.io/ethers.js/html/
      const TimeAllySIPContractFactory = new ethers.ContractFactory(
        timeallySIPJSON.abi,
        timeallySIPJSON.evm.bytecode.object,
        provider.getSigner(accounts[0])
      );
      timeallySIPInstance =  await TimeAllySIPContractFactory.deploy(esInstance.address);

      assert.ok(timeallySIPInstance.address, 'conract address should be present');
    });

    it('set a plan of TimeAllySIP', async() => {
      const args = {
        minimumCommitmentAmount: ethers.utils.parseEther('500'),
        accumulationPeriodMonths: 12,
        benefitPeriodYears: 9,
        gracePeriodSeconds: 864000, /// 10 days
        onTimeBenefitFactor: 200,
        graceBenefitFactor: 180,
        topupBenefitFactor: 100
      }
      const tx = await timeallySIPInstance.functions.createSIPPlan(
        ...Object.values(args)
      );
      await tx.wait();

      const sipPlan = await timeallySIPInstance.functions.sipPlans(0);

      assert.ok(
        sipPlan.minimumCommitmentAmount.eq(args.minimumCommitmentAmount),
        'minimumCommitmentAmount should be set properly'
      );
      assert.ok(
        sipPlan.accumulationPeriodMonths.eq(args.accumulationPeriodMonths),
        'accumulationPeriodMonths should be set properly'
      );
      assert.ok(
        sipPlan.benefitPeriodYears.eq(args.benefitPeriodYears),
        'benefitPeriodYears should be set properly'
      );
      assert.ok(
        sipPlan.gracePeriodSeconds.eq(args.gracePeriodSeconds),
        'gracePeriodSeconds should be set properly'
      );
      assert.ok(
        sipPlan.onTimeBenefitFactor.eq(args.onTimeBenefitFactor),
        'onTimeBenefitFactor should be set properly'
      );
      assert.ok(
        sipPlan.graceBenefitFactor.eq(args.graceBenefitFactor),
        'graceBenefitFactor should be set properly'
      );
      assert.ok(
        sipPlan.topupBenefitFactor.eq(args.topupBenefitFactor),
        'topupBenefitFactor should be set properly'
      );

    });
  });

  // describe('TimeAllySIP Functionality', async() => {
  //
  //   /// @dev this is first test case of this collection
  //   it('should change storage value to a new value', async() => {
  //
  //     /// @dev you sign and submit a transaction to local blockchain (ganache) initialized on line 10.
  //     const tx = await simpleStorageInstance.functions.setValue('Zemse');
  //
  //     /// @dev you can wait for transaction to confirm
  //     await tx.wait();
  //
  //     /// @dev now get the value at storage
  //     const currentValue = await simpleStorageInstance.functions.getValue();
  //
  //     /// @dev then comparing with expectation value
  //     assert.equal(
  //       currentValue,
  //       'Zemse',
  //       'value set must be able to get'
  //     );
  //   });
  // });
});
