pragma solidity 0.5.12;

import './SafeMath.sol';

/**

24 oct 19:38 in last moment im changing panther to cheetah. this might give bugs. pls check
- completed the operation. done lot of testings too. feeling confident.

remove status from sip struct
- might be required for nomineeWithdraw

make gas estimation report
- done: newSIP: 8 ERC20
- deposit: 3 ERC20
- withdraw: 2 ERC20
- 1st powerbooster: 3.5 ERC20
- 2nd & 3rd poowerbooster 1.8 ERC20

nominee can withdraw benefit after one year do this
- done

add multisig trustee / appointee
- done

power booster deduction to be sent to owner address
- no, added this to fundsDeposit B-)

create get methods for all struct mappings

make option to make plan inactivw

add condition of cap in new users creating SIP.
- added in deposit too

ensure SIP storage _sip everywhere
- ensured

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
    // uint256 status; /// @dev 1 => acc period, 2 => withdraw period
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

  event AppointeeUpdated (
    address indexed _staker,
    uint256 indexed _sipId,
    address indexed _appointeeAddress,
    bool _appointeeStatus
  );

  event AppointeeVoted (
    address indexed _staker,
    uint256 indexed _sipId,
    address indexed _appointeeAddress
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
    address _stakerAddress,
    uint256 _sipId,
    uint256 _monthId
  ) public view returns (uint256) {
    return sips[_stakerAddress][_sipId].depositStatus[_monthId];
  }

  function createSIPPlan(
    uint256 _minimumMonthlyCommitmentAmount,
    uint256 _accumulationPeriodMonths,
    uint256 _benefitPeriodYears,
    uint256 _gracePeriodSeconds,
    uint256 _monthlyBenefitFactor,
    uint256 _gracePenaltyFactor,
    uint256 _defaultPenaltyFactor
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

    uint256 _benefitsToBeGiven = _monthlyCommitmentAmount
      .mul(sipPlans[ _planId ].monthlyBenefitFactor)
      .div(1000)
      .mul(sipPlans[ _planId ].benefitPeriodYears);

    require(
      fundsDeposit >= _benefitsToBeGiven
      , 'enough funds should be there in SIP'
    );
    require(token.transferFrom(msg.sender, address(this), _monthlyCommitmentAmount));

    sips[msg.sender].push(SIP({
      planId: _planId,
      // status: 1,
      stakingTimestamp: now,
      monthlyCommitmentAmount: _monthlyCommitmentAmount,
      totalDeposited: _monthlyCommitmentAmount,
      lastWithdrawlMonthId: 0, /// @dev withdrawl monthId starts from 1
      powerBoosterWithdrawls: 0,
      numberOfAppointees: 0,
      appointeeVotes: 0
    }));

    uint256 _sipId = sips[msg.sender].length - 1;

    /// @dev marking month 1 as paid on time
    sips[msg.sender][_sipId].depositStatus[1] = 2;

    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitsToBeGiven
    );

    emit NewSIP(msg.sender, sips[msg.sender].length - 1, _monthlyCommitmentAmount);
    emit NewDeposit(msg.sender, _sipId, 1, _monthlyCommitmentAmount, _benefitsToBeGiven, msg.sender);
  }

  function getDepositStatus(address _stakerAddress, uint256 _sipId, uint256 _monthId) public view returns (uint256) {
    SIP storage _sip = sips[_stakerAddress][_sipId];

    require(
      _monthId >= 1 && _monthId
        <= sipPlans[ _sip.planId ].accumulationPeriodMonths
      , 'invalid deposit month'
    );

    /// @dev not using safemath to save gas, because _monthId is bounded.
    uint256 onTimeTimestamp = _sip.stakingTimestamp + EARTH_SECONDS_IN_MONTH * (_monthId - 1);

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

    uint256 _benefitsToBeGiven = _depositAmount
      .mul(sipPlans[ _sip.planId ].monthlyBenefitFactor)
      .div(1000)
      .mul(sipPlans[ _sip.planId ].benefitPeriodYears);

    require(
      fundsDeposit >= _benefitsToBeGiven.add(pendingBenefitAmountOfAllStakers)
      , 'enough funds should be there in SIP'
    );

    require(token.transferFrom(msg.sender, address(this), _depositAmount));

    /// @dev check if deposit is allowed according to current time
    uint256 _depositStatus = getDepositStatus(_stakerAddress, _sipId, _monthId);
    require(_depositStatus > 0, 'grace period elapsed or too early');

    _sip.depositStatus[_monthId] = _depositStatus;

    _sip.totalDeposited = _sip.totalDeposited.add(_depositAmount);
    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitsToBeGiven
    );

    emit NewDeposit(_stakerAddress, _sipId, _monthId, _depositAmount, _benefitsToBeGiven, msg.sender);
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
      if(_sip.appointeeVotes > _sip.numberOfAppointees.div(2)) {
        withdrawlAllowedTimestamp += EARTH_SECONDS_IN_MONTH * 6;
      } else {
        withdrawlAllowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
      }
    }

    require(
      _withdrawlMonthId > 0 && _withdrawlMonthId <= sipPlans[ _sip.planId ].benefitPeriodYears * 12
      , 'invalid withdraw month'
    );
    require(
      _withdrawlMonthId > _sip.lastWithdrawlMonthId
      , 'cannot withdraw again'
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
      if(_sip.appointeeVotes > _sip.numberOfAppointees.div(2)) {
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 6;
      } else {
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
      }
    }

    require(now > _allowedTimestamp, 'cannot withdraw early');

    /// @dev marking that power booster is withdrawn
    _sip.powerBoosterWithdrawls = _powerBoosterSerial;

    uint256 _powerBoosterAmount = _sip.totalDeposited.div(3);

    if(_powerBoosterSerial == 1) {
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
      uint256 _penaltyAmount = _powerBoosterAmount.mul(_totalPenaltyFactor).div(1000);

      /// @dev allocate penalty into fund.
      fundsDeposit = fundsDeposit.add(_penaltyAmount);

      _powerBoosterAmount = _powerBoosterAmount.sub(_penaltyAmount);
    }

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

  function viewNomination(address _stakerAddress, uint256 _sipId, address _nomineeAddress) public view returns (bool) {
    return sips[_stakerAddress][_sipId].nominees[_nomineeAddress];
  }

  // check all four cases in mocha
  // false -> true
  // true -> true
  // true -> false
  // false -> false
  function toogleAppointee(
    uint256 _sipId,
    address _appointeeAddress,
    bool _newAppointeeStatus
  ) public {
    SIP storage _sip = sips[msg.sender][_sipId];
    if(!_sip.appointees[_appointeeAddress] && _newAppointeeStatus) {
      /// @dev adding appointee
      _sip.numberOfAppointees = _sip.numberOfAppointees.add(1);
      _sip.nominees[_appointeeAddress] = true;

    } else if(_sip.appointees[_appointeeAddress] && !_newAppointeeStatus) {
      _sip.nominees[_appointeeAddress] = false;
      _sip.numberOfAppointees = _sip.numberOfAppointees.sub(1);
    }
    emit AppointeeUpdated(msg.sender, _sipId, _appointeeAddress, _newAppointeeStatus);
  }

  function viewAppointation(
    address _stakerAddress,
    uint256 _sipId,
    address _appointeeAddress
  ) public view returns (bool) {
    return sips[_stakerAddress][_sipId].appointees[_appointeeAddress];
  }

  function appointeeVote(
    address _stakerAddress,
    uint256 _sipId
  ) public {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    require(_sip.appointees[msg.sender]
      , 'should be appointee to cast vote'
    );
    _sip.appointees[msg.sender] = false;
    _sip.appointeeVotes = _sip.appointeeVotes.add(1);

    emit AppointeeVoted(_stakerAddress, _sipId, msg.sender);
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
