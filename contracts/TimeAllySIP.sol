pragma solidity 0.5.12;

import './SafeMath.sol';

/**

24 oct 19:38 in last moment im changing panther to cheetah. this might give bugs. pls check

work on add power booster withdrawl
- compare a different withdrawl with one transaction withdrawl
- power booster only on commitment

remove status from sip struct
- might be required for nomineeWithdraw

make gas estimation report

nominee can withdraw benefit after one year do this

add multisig trustee / appointee

power booster deduction to be sent to owner address

create get methods for all struct mappings

make option to make plan inactivw

add condition of cap in new users creating SIP.

ensure SIP storage _sip everywhere

check for DAO type vulnerabilities
**/

contract TimeAllySIP {
  using SafeMath for uint256;

  struct SIPPlan {
    bool isPlanActive;
    uint256 minimumMonthlyCommitmentAmount; /// @dev minimum monthlyCommitmentAmount
    uint256 accumulationPeriodMonths; /// @dev 12 months
    uint256 benefitPeriodYears; /// @dev 9 years
    uint256 gracePeriodSeconds;
    uint256 monthlyBenefitFactor; /// @dev this is per 1000; i.e 200 for 20%
    uint256 gracePenaltyFactor; /// @dev penalty on powerBoosterAmount, this is per 1000; i.e 10 for 1%
    uint256 defaultPenaltyFactor; /// @dev penalty on powerBoosterAmount, this is per 1000; i.e 20 for 2%
    // uint256 onTimeBenefitFactor; /// @dev this is per 1000; i.e 200 for 20%
    // uint256 graceBenefitFactor; /// @dev this is per 1000; i.e 180 for 18%
    // uint256 topupBenefitFactor; /// @dev this is per 1000; i.e 100 for 10%
  }

  struct SIP {
    uint256 planId;
    uint256 status; /// @dev 1 => acc period, 2 => withdraw period
    uint256 stakingTimestamp;
    uint256 monthlyCommitmentAmount;
    uint256 totalDeposited; /// @dev divided by accumulationPeriodMonths and multiplied by monthlyBenefitFactor and given for every benefit withdrawl
    uint256 lastWithdrawlMonthId;
    uint256 powerBoosterWithdrawls;
    uint256 numberOfAppointees;
    uint256 appointeeVotes;
    mapping(uint256 => uint256) depositStatus; /// @dev 2 => ontime, 1 => grace, 0 => defaulted
    // mapping(uint256 => uint256) monthlyBenefitAmount; /// @dev benefits given in yearly interval
    mapping(address => bool) nominees;
    mapping(address => bool) appointees;
  }

  address public owner;
  ERC20 public token;

  /// @dev 1 Year = 365.242 days for taking care of leap years
  uint256 public EARTH_SECONDS_IN_MONTH = 2629744;
  uint256 public pendingBenefitAmountOfAllStakers;
  uint256 public fundsDeposit; /// @dev deposited by company

  SIPPlan[] public sipPlans;

  mapping(address => SIP[]) public sips;

  event NewSIP (
    address indexed _staker,
    uint256 _sipId,
    uint256 _monthlyCommitmentAmount
  );

  event NewDeposit (
    address indexed _staker,
    uint256 indexed _sipId,
    uint256 _monthId,
    uint256 _depositAmount,
    uint256 _benefitQueued,
    address _depositedBy
  );

  event BenefitWithdrawl (
    address indexed _staker,
    uint256 indexed _sipId,
    uint256 _fromMonthId,
    uint256 _toMonthId,
    uint256 _withdrawlAmount,
    address _withdrawnBy
  );

  event PowerBoosterWithdrawl (
    address indexed _staker,
    uint256 indexed _sipId,
    uint256 _boosterSerial,
    uint256 _withdrawlAmount,
    address _withdrawnBy
  );

  event FundsDeposited (
    uint256 _depositAmount
  );

  event FundsWithdrawn (
    uint256 _withdrawlAmount
  );

  event NomineeUpdated (
    address indexed _staker,
    uint256 indexed _sipId,
    address indexed _nomineeAddress,
    bool _nomineeStatus
  );

  modifier onlyOwner() {
    require(msg.sender == owner, 'only deployer can call');
    _;
  }

  modifier meOrNominee(address _stakerAddress, uint256 _sipId) {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    if(msg.sender != _stakerAddress) {
      require(_sip.nominees[msg.sender], 'nomination should be there');
    }
    _;
  }

  constructor(ERC20 _token) public {
    owner = msg.sender;
    token = _token;
  }

  function getDepositDoneStatus(
    address _userAddress,
    uint256 _sipId,
    uint256 _monthId
  ) public view returns (uint256) {
    return sips[_userAddress][_sipId].depositStatus[_monthId];
  }

  function createSIPPlan(
    uint256 _minimumMonthlyCommitmentAmount,
    uint256 _accumulationPeriodMonths,
    uint256 _benefitPeriodYears,
    uint256 _gracePeriodSeconds,
    uint256 _monthlyBenefitFactor,
    uint256 _gracePenaltyFactor,
    uint256 _defaultPenaltyFactor
    // uint256 _onTimeBenefitFactor,
    // uint256 _graceBenefitFactor,
    // uint256 _topupBenefitFactor
  ) public onlyOwner {
    sipPlans.push(SIPPlan({
      isPlanActive: true,
      minimumMonthlyCommitmentAmount: _minimumMonthlyCommitmentAmount,
      accumulationPeriodMonths: _accumulationPeriodMonths,
      benefitPeriodYears: _benefitPeriodYears,
      gracePeriodSeconds: _gracePeriodSeconds,
      monthlyBenefitFactor: _monthlyBenefitFactor,
      gracePenaltyFactor: _gracePenaltyFactor,
      defaultPenaltyFactor: _defaultPenaltyFactor
      // onTimeBenefitFactor: _onTimeBenefitFactor,
      // graceBenefitFactor: _graceBenefitFactor,
      // topupBenefitFactor: _topupBenefitFactor
    }));
  }

  function addFunds(uint256 _depositAmount) public {
    require(token.transferFrom(msg.sender, address(this), _depositAmount));
    fundsDeposit = fundsDeposit.add(_depositAmount);

    emit FundsDeposited(_depositAmount);
  }

  function withdrawFunds(uint256 _withdrawlAmount) public onlyOwner {
    require(
      fundsDeposit.sub(pendingBenefitAmountOfAllStakers) >= _withdrawlAmount
      , 'cannot withdraw excess funds'
    );

    fundsDeposit = fundsDeposit.sub(_withdrawlAmount);
    token.transfer(msg.sender, _withdrawlAmount);

    emit FundsWithdrawn(_withdrawlAmount);
  }

  function newSIP(
    uint256 _planId,
    uint256 _monthlyCommitmentAmount
  ) public {
    require(
      _monthlyCommitmentAmount >= sipPlans[_planId].minimumMonthlyCommitmentAmount
      , 'amount should be atleast minimum'
    );
    require(token.transferFrom(msg.sender, address(this), _monthlyCommitmentAmount));

    sips[msg.sender].push(SIP({
      planId: _planId,
      status: 1,
      stakingTimestamp: now,
      monthlyCommitmentAmount: _monthlyCommitmentAmount,
      totalDeposited: _monthlyCommitmentAmount,
      lastWithdrawlMonthId: 0, /// @dev withdrawl monthId starts from 1
      powerBoosterWithdrawls: 0,
      numberOfAppointees: 0,
      appointeeVotes: 0
    }));

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _monthlyCommitmentAmount
        .mul(sipPlans[_planId].monthlyBenefitFactor)
        .div(1000)
        .mul(sipPlans[_planId].benefitPeriodYears)
    );

    uint256 _sipId = sips[msg.sender].length - 1;

    // /// @dev this is not required, commenting
    // uint256 _yearlyBenefitAmount = _monthlyCommitmentAmount.mul(sipPlans[ _planId ].onTimeBenefitFactor).div(1000);

    /// @dev marking month 1 as paid on time
    sips[msg.sender][_sipId].depositStatus[1] = 2;

    uint256 _benefitQueued = _monthlyCommitmentAmount
      .mul(sipPlans[ _planId ].monthlyBenefitFactor)
      .div(1000)
      .mul(sipPlans[ _planId ].benefitPeriodYears);

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitQueued
    );

    emit NewSIP(msg.sender, sips[msg.sender].length - 1, _monthlyCommitmentAmount);
    emit NewDeposit(msg.sender, _sipId, 1, _monthlyCommitmentAmount, _benefitQueued, msg.sender);
  }

  function getDepositStatus(address _userAddress, uint256 _sipId, uint256 _monthId) public view returns (uint256) {
    SIP storage _sip = sips[_userAddress][_sipId];

    require(
      _monthId >= 1 && _monthId
        <= sipPlans[ _sip.planId ].accumulationPeriodMonths
      , 'invalid deposit month'
    );

    /// @dev not using safemath to save gas, because _monthId is bounded.
    uint256 onTimeTimestamp = _sip.stakingTimestamp + EARTH_SECONDS_IN_MONTH * _monthId;

    /// @dev deposit allowed only one month before deadline
    if(onTimeTimestamp >= now && now >= onTimeTimestamp - EARTH_SECONDS_IN_MONTH) {
      return 2; /// @dev means deposit is ontime
    } else if(onTimeTimestamp + sipPlans[ _sip.planId ].gracePeriodSeconds >= now) {
      return 1; /// @dev means deposit is in grace period
    } else {
      return 0; /// @dev means even grace period is elapsed or early
    }
  }

  function monthlyDeposit(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _depositAmount,
    uint256 _monthId
  ) public meOrNominee(_stakerAddress, _sipId) {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    require(
      _depositAmount >= _sip.monthlyCommitmentAmount
      , 'deposit cannot be less than commitment'
    );

    /// @dev cannot deposit again
    require(
      _sip.depositStatus[_monthId] == 0
      , 'cannot deposit again'
    );

    require(token.transferFrom(msg.sender, address(this), _depositAmount));

    uint256 _depositStatus = getDepositStatus(_stakerAddress, _sipId, _monthId);

    /// @dev check if deposit is allowed according to current time
    require(_depositStatus > 0, 'grace period elapsed or too early');

    _sip.depositStatus[_monthId] = _depositStatus;
    /// @dev _yearlyBenefitAmount is benefit queued to be withdrawn after accumulation
    // uint256 _yearlyBenefitAmount = _sip.monthlyCommitmentAmount;
    // if(_depositStatus == 1) {
    //   _yearlyBenefitAmount = _yearlyBenefitAmount.mul(
    //     sipPlans[ _sip.planId ].onTimeBenefitFactor
    //   ).div(1000);
    // } else {
    //   _yearlyBenefitAmount = _yearlyBenefitAmount.mul(
    //     sipPlans[ _sip.planId ].graceBenefitFactor
    //   ).div(1000);
    // }
    //
    // if(_depositAmount > _sip.monthlyCommitmentAmount) {
    //   _yearlyBenefitAmount = _yearlyBenefitAmount.add(
    //     _depositAmount
    //     .sub(_sip.monthlyCommitmentAmount)
    //     .mul(sipPlans[ _sip.planId ].topupBenefitFactor)
    //     .div(1000)
    //   );
    // }

    _sip.totalDeposited = _sip.totalDeposited.add(_depositAmount);
    //
    // uint256 _monthIdModulus = _monthId%12;
    // if(_monthIdModulus == 0) _monthIdModulus = 12;
    // _sip.monthlyBenefitAmount[_monthIdModulus] = _yearlyBenefitAmount;

    // uint256 _benefitQueued = _yearlyBenefitAmount.mul(sipPlans[ _sip.planId ].benefitPeriodYears);

    uint256 _benefitQueued = _depositAmount
      .mul(sipPlans[ _sip.planId ].monthlyBenefitFactor)
      .div(1000)
      .mul(sipPlans[ _sip.planId ].benefitPeriodYears);

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitQueued
    );

    emit NewDeposit(_stakerAddress, _sipId, _monthId, _depositAmount, _benefitQueued, msg.sender);
  }

  function getPendingWithdrawlAmount(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _withdrawlMonthId,
    bool _isNomineeWithdrawing
  ) public view returns (uint256) {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    uint256 withdrawlAllowedTimestamp
      = _sip.stakingTimestamp
        + EARTH_SECONDS_IN_MONTH * (
          sipPlans[ _sip.planId ].accumulationPeriodMonths
            + _withdrawlMonthId - 1
        );

    if(_isNomineeWithdrawing) {
      withdrawlAllowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
    }
    require(
      _withdrawlMonthId > _sip.lastWithdrawlMonthId
      , 'cannot withdraw again'
    );
    require(
      _withdrawlMonthId <= sipPlans[ _sip.planId ].benefitPeriodYears * 12
      , 'withdraw month exceeded'
    );
    require(now >= withdrawlAllowedTimestamp
      , 'cannot withdraw early'
    );
    uint256 _averageMonthlyDeposit = _sip.totalDeposited
      .div(sipPlans[ _sip.planId ].accumulationPeriodMonths);
    uint256 _singleMonthBenefit = _averageMonthlyDeposit
      .mul(sipPlans[ _sip.planId ].monthlyBenefitFactor)
      .div(1000);
    uint256 _benefitToGive = _singleMonthBenefit.mul(
      _withdrawlMonthId.sub(_sip.lastWithdrawlMonthId)
    );
    return _benefitToGive;
  }

  function withdrawBenefit(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _withdrawlmonthId
  ) public meOrNominee(_stakerAddress, _sipId) {
    /// @dev require statements are in this function getPendingWithdrawlAmount
    uint256 _withdrawlAmount = getPendingWithdrawlAmount(
      _stakerAddress,
      _sipId,
      _withdrawlmonthId,
      msg.sender != _stakerAddress /// @dev _isNomineeWithdrawing
    );

    SIP storage _sip = sips[_stakerAddress][_sipId];

    /// @dev marking that user has withdrawn upto _withdrawlmonthId month
    uint256 _lastWithdrawlMonthId = _sip.lastWithdrawlMonthId;
    _sip.lastWithdrawlMonthId = _withdrawlmonthId;

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.sub(_withdrawlAmount);
    fundsDeposit = fundsDeposit.sub(_withdrawlAmount);

    /// @dev transfering tokens to the user wallet address
    token.transfer(msg.sender, _withdrawlAmount);

    emit BenefitWithdrawl(
      _stakerAddress,
      _sipId,
      _lastWithdrawlMonthId + 1,
      _withdrawlmonthId,
      _withdrawlAmount,
      msg.sender
    );
  }

  function calculatePowerBooster(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _boosterSerial
  ) public view returns (uint256) {
    SIP storage _sip = sips[_stakerAddress][_sipId];

    uint256 _powerBoosterAmount = _sip.monthlyCommitmentAmount
      .mul(sipPlans[ _sip.planId ].accumulationPeriodMonths).div(3);

    if(_boosterSerial == 1) {
      uint256 _totalPenaltyFactor;
      for(uint256 i = 1; i <= sipPlans[ _sip.planId ].accumulationPeriodMonths; i++) {
        if(_sip.depositStatus[i] == 0) {
          /// @dev defaulted
          _totalPenaltyFactor += sipPlans[ _sip.planId ].defaultPenaltyFactor;
        } else if(_sip.depositStatus[i] == 1) {
          /// @dev grace period
          _totalPenaltyFactor += sipPlans[ _sip.planId ].gracePenaltyFactor;
        }
      }
      _powerBoosterAmount = _powerBoosterAmount.mul(uint256(1000).sub(_totalPenaltyFactor)).div(1000);
    }

    return _powerBoosterAmount;
  }

  function withdrawPowerBooster(
    address _stakerAddress,
    uint256 _sipId
  ) public meOrNominee(_stakerAddress, _sipId) {
    SIP storage _sip = sips[_stakerAddress][_sipId];

    require(_sip.powerBoosterWithdrawls < 3, 'only 3 power boosters');
    uint256 _powerBoosterSerial = _sip.powerBoosterWithdrawls + 1;

    /// @dev not using SafeMath because range is safe
    uint256 _allowedTimestamp = _sip.stakingTimestamp
      + sipPlans[ _sip.planId ].accumulationPeriodMonths * EARTH_SECONDS_IN_MONTH
      + sipPlans[ _sip.planId ].benefitPeriodYears * 12 * EARTH_SECONDS_IN_MONTH * _powerBoosterSerial / 3 - EARTH_SECONDS_IN_MONTH;

    if(msg.sender != _stakerAddress) {
      _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
    }
    require(now > _allowedTimestamp, 'cannot withdraw early');

    uint256 _powerBoosterAmount = calculatePowerBooster(_stakerAddress, _sipId, _powerBoosterSerial);

    /// @dev marking that power booster is withdrawn
    _sip.powerBoosterWithdrawls = _powerBoosterSerial;

    token.transfer(msg.sender, _powerBoosterAmount);

    emit PowerBoosterWithdrawl(
      _stakerAddress,
      _sipId,
      _powerBoosterSerial,
      _powerBoosterAmount,
      msg.sender
    );
  }

  function toogleNominee(uint256 _sipId, address _nomineeAddress, bool _newNomineeStatus) public {
    sips[msg.sender][_sipId].nominees[_nomineeAddress] = _newNomineeStatus;
    emit NomineeUpdated(msg.sender, _sipId, _nomineeAddress, _newNomineeStatus);
  }

  function viewNomination(address _userAddress, uint256 _sipId, address _nomineeAddress) public view returns (bool) {
    return sips[_userAddress][_sipId].nominees[_nomineeAddress];
  }

  function getTime() public view returns (uint256) {
    return now;
  }
}

/// @dev For interface requirement
contract ERC20 {
  function balanceOf(address _owner) public view returns (uint256 balance);
  function transfer(address _to, uint256 _value) public returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
}

/// @dev TimeAlly Smart Contract (that rewards from NRT Manager). Purpose is to sync with the NRT month number.
contract TimeAlly {
  function getCurrentMonth() public view returns (uint256);
}
