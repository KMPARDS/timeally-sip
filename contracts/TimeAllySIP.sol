pragma solidity 0.5.12;

import './SafeMath.sol';

/**
Month number:
0
1
2
3
4
5
6
7
8
9
10
11
**/

contract TimeAllySIP {
  using SafeMath for uint256;

  struct SIPPlan {
    bool isPlanActive;
    uint256 minimumMonthlyCommitmentAmount; /// @dev minimum monthlyCommitmentAmount
    uint256 accumulationPeriodMonths; /// @dev 12 months
    uint256 benefitPeriodYears; /// @dev 9 years
    uint256 gracePeriodSeconds;
    uint256 onTimeBenefitFactor; /// @dev this is per 1000; i.e 200 for 20%
    uint256 graceBenefitFactor; /// @dev this is per 1000; i.e 180 for 18%
    uint256 topupBenefitFactor; /// @dev this is per 1000; i.e 100 for 10%
  }

  struct SIP {
    uint256 planId;
    uint256 status; /// @dev 1 => acc period, 2 => withdraw period
    uint256 stakingTimestamp;
    uint256 monthlyCommitmentAmount;
    uint256 ctcAmount; /// @dev this amount is deposited by company for benefits
    uint256 pendingBenefitAmount; /// @dev increased everytime staker deposits
    uint256 powerBoosterAmount; /// @dev increased everytime staker deposits
    uint256 lastWithdrawlMonthId;
    mapping(uint256 => uint256) monthlyBenefitAmount; /// @dev benefits given in yearly interval
  }

  address public owner;
  ERC20 public token;

  /// @dev 1 Year = 365.242 days for taking care of leap years
  uint256 public EARTH_SECONDS_IN_MONTH = 2629744;

  SIPPlan[] public sipPlans;

  mapping(address => SIP[]) public sips;

  event NewSIP (
    address indexed _staker,
    uint256 _sipId,
    uint256 _monthlyCommitmentAmount
  );

  event NewDeposit (
    address indexed _staker,
    uint256 _sipId,
    uint256 _depositAmount,
    uint256 _yearlyBenefitAmount
  );

  event BenefitWithdrawl (
    address indexed _staker,
    uint256 indexed _sipId,
    uint256 _fromMonthId,
    uint256 _toMonthId,
    uint256 _withdrawlAmount
  );

  modifier onlyOwner() {
    require(msg.sender == owner, 'only deployer can call');
    _;
  }

  constructor(ERC20 _token) public {
    owner = msg.sender;
    token = _token;
  }

  function monthlyBenefitAmount(
    address _userAddress,
    uint256 _sipId,
    uint256 _monthId
  ) public view returns (uint256) {
    return sips[_userAddress][_sipId].monthlyBenefitAmount[_monthId];
  }

  function createSIPPlan(
    uint256 _minimumMonthlyCommitmentAmount,
    uint256 _accumulationPeriodMonths,
    uint256 _benefitPeriodYears,
    uint256 _gracePeriodSeconds,
    uint256 _onTimeBenefitFactor,
    uint256 _graceBenefitFactor,
    uint256 _topupBenefitFactor
  ) public onlyOwner {
    sipPlans.push(SIPPlan({
      isPlanActive: true,
      accumulationPeriodMonths: _accumulationPeriodMonths,
      minimumMonthlyCommitmentAmount: _minimumMonthlyCommitmentAmount,
      benefitPeriodYears: _benefitPeriodYears,
      gracePeriodSeconds: _gracePeriodSeconds,
      onTimeBenefitFactor: _onTimeBenefitFactor,
      graceBenefitFactor: _graceBenefitFactor,
      topupBenefitFactor: _topupBenefitFactor
    }));
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

    /// @dev old code of using array data structure just in case required
    // SIP memory _userSIP;
    // _userSIP.planId = _planId;
    // _userSIP.stakingTimestamp = now;
    // _userSIP.monthlyCommitmentAmount = _monthlyCommitmentAmount;
    // _userSIP.ctcAmount = 0;
    // _userSIP.pendingBenefitAmount = _monthlyCommitmentAmount.mul(sipPlans[_planId].benefitPeriodYears);
    // _userSIP.powerBoosterAmount = _monthlyCommitmentAmount;
    // sips[msg.sender].push(_userSIP);
    // uint256 _sipId = sips[msg.sender].length - 1;
    // sips[msg.sender][_sipId].monthlyBenefitAmount.push(_monthlyCommitmentAmount);

    sips[msg.sender].push(SIP({
      planId: _planId,
      status: 1,
      stakingTimestamp: now,
      monthlyCommitmentAmount: _monthlyCommitmentAmount,
      ctcAmount: 0,
      pendingBenefitAmount: _monthlyCommitmentAmount.mul(sipPlans[_planId].benefitPeriodYears),
      powerBoosterAmount: _monthlyCommitmentAmount,
      lastWithdrawlMonthId: 0 /// @dev withdrawl monthId starts from 1, monthId is 0
    }));

    /// @dev commenting this setep to save gas
    uint256 _sipId = sips[msg.sender].length - 1;
    sips[msg.sender][_sipId].monthlyBenefitAmount[0] = _monthlyCommitmentAmount;

    emit NewSIP(msg.sender, sips[msg.sender].length - 1, _monthlyCommitmentAmount);
  }

  function getDepositStatus(address _userAddress, uint256 _sipId, uint256 _monthId) public view returns (uint256) {
    SIP storage _sip = sips[_userAddress][_sipId];

    /// @dev not using safemath to save gas, function is private and used
    /// in monthlyDeposit where _monthId is bounded.
    uint256 onTimeTimestamp = _sip.stakingTimestamp + EARTH_SECONDS_IN_MONTH * _monthId;

    if(onTimeTimestamp >= now) {
      return 1; /// @dev means deposit is ontime
    } else if(onTimeTimestamp + sipPlans[ _sip.planId ].gracePeriodSeconds >= now) {
      return 2; /// @dev means deposit is in grace period
    } else {
      return 3; /// @dev means even grace period is elapsed
    }
  }

  function monthlyDeposit(
    uint256 _sipId,
    uint256 _depositAmount,
    uint256 _monthId
  ) public {
    SIP storage _sip = sips[msg.sender][_sipId];
    require(
      _depositAmount >= _sip.monthlyCommitmentAmount
      , 'deposit cannot be less than commitment'
    );
    require(
      _monthId >= 0 && _monthId
        < sipPlans[ _sip.planId ].accumulationPeriodMonths
      , 'invalid month'
    );
    require(
      _sip.monthlyBenefitAmount[_monthId] == 0
      , 'cannot deposit again'
    );

    require(token.transferFrom(msg.sender, address(this), _depositAmount));

    uint256 _depositStatus = getDepositStatus(msg.sender, _sipId, _monthId);
    require(_depositStatus < 3, 'grace period elapsed');

    /// @dev _yearlyBenefitAmount is benefit queued to be withdrawn after accumulation
    uint256 _yearlyBenefitAmount = _sip.monthlyCommitmentAmount;
    if(_depositStatus == 1) {
      _yearlyBenefitAmount = _yearlyBenefitAmount.mul(
        sipPlans[ _sip.planId ].onTimeBenefitFactor
      ).div(1000);
    } else {
      _yearlyBenefitAmount = _yearlyBenefitAmount.mul(
        sipPlans[ _sip.planId ].graceBenefitFactor
      ).div(1000);
    }

    if(_depositAmount > _sip.monthlyCommitmentAmount) {
      _yearlyBenefitAmount = _yearlyBenefitAmount.add(
        _depositAmount
        .sub(_sip.monthlyCommitmentAmount)
        .mul(sipPlans[ _sip.planId ].topupBenefitFactor)
        .div(1000)
      );
    }

    _sip.powerBoosterAmount = _sip.powerBoosterAmount.add(_depositAmount);
    _sip.monthlyBenefitAmount[_monthId%12] = _yearlyBenefitAmount;
    _sip.pendingBenefitAmount = _sip.pendingBenefitAmount.add(
      _yearlyBenefitAmount.mul(sipPlans[ _sip.planId ].benefitPeriodYears)
    );

    emit NewDeposit(msg.sender, _sipId, _depositAmount, _yearlyBenefitAmount);
  }

  function getPendingWithdrawlAmount(
    address _userAddress,
    uint256 _sipId,
    uint256 _withdrawlmonthId
  ) public view returns (uint256) {
    SIP storage _sip = sips[_userAddress][_sipId];
    uint256 withdrawlAllowedTimestamp
      = _sip.stakingTimestamp
        + EARTH_SECONDS_IN_MONTH * (
          sipPlans[ _sip.planId ].accumulationPeriodMonths
            + _withdrawlmonthId
        );
    require(
      _withdrawlmonthId > _sip.lastWithdrawlMonthId
      , 'cannot withdraw again'
    );
    require(
      _withdrawlmonthId <= sipPlans[ _sip.planId ].benefitPeriodYears * 12
      , 'withdraw month exceeded'
    );
    require(now >= withdrawlAllowedTimestamp
      , 'cannot withdraw early'
    );
    uint256 _benefitToGive;
    for(uint256 _i = _sip.lastWithdrawlMonthId + 1; _i <= _withdrawlmonthId; _i++) {
      _benefitToGive = _benefitToGive.add(_sip.monthlyBenefitAmount[_i%12]);
    }
    return _benefitToGive;
  }

  function withdrawBenefit(
    uint256 _sipId,
    uint256 _withdrawlmonthId
  ) public {
    SIP storage _sip = sips[msg.sender][_sipId];
    uint256 _lastWithdrawlMonthId = _sip.lastWithdrawlMonthId;
    require(_sip.status == 2, 'not in withdraw mode');
    uint256 _withdrawlAmount = getPendingWithdrawlAmount(
      msg.sender,
      _sipId,
      _withdrawlmonthId
    );

    /// @dev marking that user has withdrawn upto _withdrawlmonthId month
    _sip.lastWithdrawlMonthId = _withdrawlmonthId;

    /// @dev transfering tokens to the user wallet address
    token.transfer(msg.sender, _sipId);

    // _lastWithdrawlMonth
    emit BenefitWithdrawl(
      msg.sender,
      _sipId,
      _lastWithdrawlMonthId + 1,
      _withdrawlmonthId,
      _withdrawlAmount
    );
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
