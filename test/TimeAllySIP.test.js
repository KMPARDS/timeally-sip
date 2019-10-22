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

/// @dev helper function
const _convertDataToHex = (data, index = 0) => {
  return '0x'+data.slice(2+64*index, 2+64*(index+1));
}

/// @dev importing build file
const esJson = require('../build/Eraswap_ERC20Basic.json');
const timeallySIPJSON = require('../build/TimeAllySIP_TimeAllySIP.json');

const EARTH_SECONDS_IN_MONTH = 2629744;
let evm_increasedTime = 0;
/// @dev initialize global variables
let accounts
, esInstance = []
, timeallySIPInstance = [];


const sipPlans = [
  {
    minimumMonthlyCommitmentAmount: ethers.utils.parseEther('500'),
    accumulationPeriodMonths: 12,
    benefitPeriodYears: 9,
    gracePeriodSeconds: 864000, /// 10 days
    onTimeBenefitFactor: 200,
    graceBenefitFactor: 180,
    topupBenefitFactor: 100
  }
];
let diff = 0;
const safeDeposit = (seconds, add = 0) => {
  diff += add;
  return seconds - 1 - diff + add;
};
const depositTestCases = [
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    1
  ],
  [
    0,
    '500',
    1,
    'fail'
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH, 1000),
    '600',
    2
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '1000',
    3
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '1000',
    4
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    5
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    6
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    7
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    8
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    9
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    10
  ],
  [
    safeDeposit(EARTH_SECONDS_IN_MONTH),
    '600',
    11
  ],
  // [
  //   safeDeposit(EARTH_SECONDS_IN_MONTH),
  //   '600',
  //   12
  // ],
  // [
  //   safeDeposit(EARTH_SECONDS_IN_MONTH),
  //   '600',
  //   13
  // ],
];


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
    esInstance[0] =  await EraswapContractFactory.deploy();

    assert.ok(esInstance[0].address, 'conract address should be present');
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
      timeallySIPInstance[0] =  await TimeAllySIPContractFactory.deploy(esInstance[0].address);

      assert.ok(timeallySIPInstance[0].address, 'conract address should be present');
    });

    it('set a plan of TimeAllySIP', async() => {
      const args = sipPlans[0];
      const tx = await timeallySIPInstance[0].functions.createSIPPlan(
        ...Object.values(args)
      );
      await tx.wait();

      const sipPlan = await timeallySIPInstance[0].functions.sipPlans(0);

      assert.ok(
        sipPlan.minimumMonthlyCommitmentAmount.eq(args.minimumMonthlyCommitmentAmount),
        'minimumMonthlyCommitmentAmount should be set properly'
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

  describe('TimeAllySIP Functionality', async() => {

    describe('New TimeAlly SIP', async() => {
      it('deployer sends 10,000 ES to account 1', async() => {
        const tx = await esInstance[0].functions.transfer(
          accounts[1],
          ethers.utils.parseEther('10000')
        );

        await tx.wait();

        const balanceOf1 = await esInstance[0].balanceOf(accounts[1]);

        assert.ok(balanceOf1.eq(ethers.utils.parseEther('10000')), 'account 1 should get 10,000 ES');
      });

      it('account 1 gives allowance of 500 ES to TimeAllySIP Contract', async() => {
        esInstance[1] = new ethers.Contract(
          esInstance[0].address,
          esJson.abi,
          provider.getSigner(accounts[1])
        );

        const tx = await esInstance[1].functions.approve(timeallySIPInstance[0].address, ethers.utils.parseEther('500'));
        await tx.wait();

        const allowanceToSip = await esInstance[1].functions.allowance(accounts[1], timeallySIPInstance[0].address);

        assert.ok(allowanceToSip.eq(ethers.utils.parseEther('500')), 'allowance should be set');
      });

      it('account 1 tries to create an SIP of 400 ES, should fail with plan id 0', async() => {
        timeallySIPInstance[1] = new ethers.Contract(
          timeallySIPInstance[0].address,
          timeallySIPJSON.abi,
          provider.getSigner(accounts[1])
        );

        try {
          const tx = await timeallySIPInstance[1].functions.newSIP(0, ethers.utils.parseEther('400'));
          await tx.wait();
          assert(false, 'amount less than 500 ES should throw error');
        } catch (error) {
          assert.ok(error.message.includes('revert amount should be atleast minimum'), 'error should be of revert and amount should be atleast minimum')
        }
      });

      it('account 1 tries to create an SIP of 500 ES monthly commitment', async() => {
        const beforeBalanceOf1 = await esInstance[0].balanceOf(accounts[1]);
        const tx = await timeallySIPInstance[1].functions.newSIP(0, ethers.utils.parseEther('500'));
        await tx.wait();

        const afterBalanceOf1 = await esInstance[0].balanceOf(accounts[1]);

        assert.ok(
          beforeBalanceOf1
          .sub(afterBalanceOf1)
          .eq(ethers.utils.parseEther('500')),
          'amount subtracted from account 1 should be 500'
        );

        // for(i = 0; i <= 11; i++) {
        //   console.log(i, ethers.utils.formatEther(await timeallySIPInstance[1].functions.monthlyBenefitAmount(accounts[1], 0, i)));
        // }

        /// add checks for sip details too.
      });
    });

    describe('Continue TimeAlly SIP deposits', async() => {
      depositTestCases.forEach(entry => {
        const [increaseSeconds, amountInES, monthNumber, fail] = entry;
        describe(`Deposit of Month ${monthNumber}`, async() => {
          if(increaseSeconds) {
            it(`time travels to future by ${increaseSeconds} seconds`, async() => {
              evm_increasedTime += increaseSeconds;
              const timeIncreased = await provider.send('evm_increaseTime', [increaseSeconds]);

              assert.equal(timeIncreased, evm_increasedTime, 'increase in time should be one month');
            });
          }

          it(`gives allowance of ${amountInES} ES to TimeAlly SIP contract`, async() => {
            const tx = await esInstance[1].functions.approve(timeallySIPInstance[0].address, ethers.utils.parseEther(amountInES));
            await tx.wait();

            const allowanceToSip = await esInstance[1].functions.allowance(accounts[1], timeallySIPInstance[0].address);

            assert.ok(allowanceToSip.eq(ethers.utils.parseEther(amountInES)), 'allowance should be set');
          });

          it(`depositing ${amountInES} ES in SIP month ${monthNumber}${fail ? ` should give error` : ''}`, async() => {
            try {
              const depositStatus = await timeallySIPInstance[1].functions.getDepositStatus(
                accounts[1], 0, monthNumber
              );
              const actualDepositAmountBN = ethers.utils.parseEther(amountInES);
              const tx = await timeallySIPInstance[1].functions.monthlyDeposit(
                0, actualDepositAmountBN, monthNumber
              );
              const txReceipt = await tx.wait();
              const log = txReceipt.logs[1];
              // console.log(log);
              const depositAmount = ethers.utils.bigNumberify(_convertDataToHex(log.data, 1));
              const yearlyBenefit = ethers.utils.bigNumberify(_convertDataToHex(log.data, 2));

              console.log("\x1b[2m",
                `        depositStatus: ${Number(depositStatus._hex)}\n`,
                `        monthNumber: ${monthNumber}\n`,
                `        deposit amount: ${ethers.utils.formatEther(depositAmount)}\n`,
                `        yearly benefit queued: ${ethers.utils.formatEther(yearlyBenefit)}`
              );
              // for(i = 0; i <= 11; i++) {
              //   console.log("\x1b[2m",i, ethers.utils.formatEther(await timeallySIPInstance[1].functions.monthlyBenefitAmount(accounts[1], 0, i)));
              // }
            } catch (error) {
              assert(fail);
            }
          });
        })
      });
    });

    // describe('TimeAlly SIP Withdrawls', async() => {
    //   it('', async() => {
    //
    //   });
    // });

  });
});
