pragma solidity 0.5.12;

import './SafeMath.sol';

/**

24 oct 19:38 in last moment im changing panther to cheetah. this might give bugs. pls check
- completed the operation. done lot of testings too. feeling confident.

remove status from sip struct
- might be required for nomineeWithdraw
- removed it

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

check appointee cases:
// check all four cases in mocha
// false -> true
// true -> true
// true -> false
// false -> false

**/

/// @title TimeAlly Super Goal Achiever Plan (TSGAP)
/// @author The EraSwap Team
/// @notice The benefits are transparently stored in advance in this contract
contract TimeAllySIP {
  using SafeMath for uint256;

  struct SIPPlan {
    bool isPlanActive;
    uint256 minimumMonthlyCommitmentAmount; /// @dev minimum amount 500 ES
    uint256 accumulationPeriodMonths; /// @dev 12 months
    uint256 benefitPeriodYears; /// @dev 9 years
    uint256 gracePeriodSeconds; /// @dev 60*60*24*10
    uint256 monthlyBenefitFactor; /// @dev this is per 1000; i.e 200 for 20%
    uint256 gracePenaltyFactor; /// @dev penalty on first powerBoosterAmount, this is per 1000; i.e 10 for 1%
    uint256 defaultPenaltyFactor; /// @dev penalty on first powerBoosterAmount, this is per 1000; i.e 20 for 2%
  }

  struct SIP {
    uint256 planId;
    uint256 stakingTimestamp;
    uint256 monthlyCommitmentAmount;
    uint256 totalDeposited; /// @dev divided by accumulationPeriodMonths and multiplied by monthlyBenefitFactor and given for every benefit withdrawl
    uint256 lastWithdrawlMonthId;
    uint256 powerBoosterWithdrawls;
    uint256 numberOfAppointees;
    uint256 appointeeVotes;
    mapping(uint256 => uint256) depositStatus; /// @dev 2 => ontime, 1 => grace, 0 => defaulted / not yet
    mapping(address => bool) nominees;
    mapping(address => bool) appointees;
  }

  address public owner;
  ERC20 public token;

  /// @dev 1 Year = 365.242 days for taking care of leap years
  uint256 public EARTH_SECONDS_IN_MONTH = 2629744;

  /// @dev whenever a deposit is done by user, benefit amount (to be paid
  /// in due plan time) will be already added to this. and in case of withdrawl,
  /// it is subtracted from this.
  uint256 public pendingBenefitAmountOfAllStakers;

  /// @dev deposited by Era Swap Donors. It is given as benefits to  ES stakers.
  /// on every withdrawl this deposit is reduced, and on some point of time
  /// if enough fundsDeposit is not available to assure staker benefit,
  /// contract will allow staker to deposit
  uint256 public fundsDeposit;

  SIPPlan[] public sipPlans;
  mapping(address => SIP[]) public sips;

  event FundsDeposited (
    uint256 _depositAmount
  );

  event FundsWithdrawn (
    uint256 _withdrawlAmount
  );

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

  /// @dev restricting access to some functionalities to admin
  modifier onlyOwner() {
    require(msg.sender == owner, 'only deployer can call');
    _;
  }

  /// @dev restricting access of staker's SIP to them and their nominees
  modifier meOrNominee(address _stakerAddress, uint256 _sipId) {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    if(msg.sender != _stakerAddress) {
      require(_sip.nominees[msg.sender], 'nomination should be there');
    }
    _;
  }

  /// @notice sets up TimeAllySIP contract when deployed
  /// @param _token: is EraSwap ERC20 Smart Contract Address
  constructor(ERC20 _token) public {
    owner = msg.sender;
    token = _token;
  }

  /// @notice this function is used by owner to create plans for new SIPs
  /// @param _minimumMonthlyCommitmentAmount: minimum SIP monthly amount in exaES
  /// @param _accumulationPeriodMonths: number of months to deposit commitment amount
  /// @param _benefitPeriodYears: number of years of benefit
  /// @param _gracePeriodSeconds: grace allowance to stakers to deposit monthly
  /// @param _monthlyBenefitFactor: this is per 1000; i.e 200 for 20%
  /// @param _gracePenaltyFactor: due to late deposits, this is per 1000
  /// @param _defaultPenaltyFactor: due to missing deposits, this is per 1000
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

  /// @notice this function is used by donors to add funds to fundsDeposit
  /// @dev ERC20 approve is required to be done for this contract earlier
  /// @param _depositAmount: amount in exaES to deposit
  function addFunds(uint256 _depositAmount) public {
    require(
      token.transferFrom(msg.sender, address(this), _depositAmount)
      , 'tokens should be transfered'
    );
    fundsDeposit = fundsDeposit.add(_depositAmount);

    emit FundsDeposited(_depositAmount);
  }

  /// @notice this is used by owner to withdraw ES that are not allocated to any SIP
  /// @param _withdrawlAmount: amount in exaES to withdraw
  function withdrawFunds(uint256 _withdrawlAmount) public onlyOwner {
    require(
      fundsDeposit.sub(pendingBenefitAmountOfAllStakers) >= _withdrawlAmount
      , 'cannot withdraw excess funds'
    );

    fundsDeposit = fundsDeposit.sub(_withdrawlAmount);
    token.transfer(msg.sender, _withdrawlAmount);

    emit FundsWithdrawn(_withdrawlAmount);
  }

  /// @notice this function is used to initiate a new SIP along with first deposit
  /// @dev ERC20 approve is required to be done for this contract earlier, also
  ///  fundsDeposit should be enough otherwise contract will not accept
  /// @param _planId: choose a SIP plan
  /// @param _monthlyCommitmentAmount: needs to be more than minimum specified in plan.
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
      , 'enough funds for benefits should be there in contract'
    );
    require(token.transferFrom(msg.sender, address(this), _monthlyCommitmentAmount));

    sips[msg.sender].push(SIP({
      planId: _planId,
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

    /// @dev incrementing pending benefits
    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitsToBeGiven
    );

    emit NewSIP(
      msg.sender,
      sips[msg.sender].length - 1,
      _monthlyCommitmentAmount
    );

    emit NewDeposit(
      msg.sender,
      _sipId,
      1,
      _monthlyCommitmentAmount,
      _benefitsToBeGiven,
      msg.sender
    );
  }

  /// @notice this function is used to do monthly commitment deposit of SIP
  /// @dev ERC20 approve is required to be done for this contract earlier, also
  ///  fundsDeposit should be enough otherwise contract will not accept
  ///  Also, deposit can also be done by any nominee of this SIP.
  /// @param _stakerAddress: address of staker who has an SIP
  /// @param _sipId: id of SIP in staker address portfolio
  /// @param _depositAmount: amount to deposit,
  /// @param _monthId: specify the month to deposit
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

    /// @dev cannot deposit again for a month in which a deposit is already done
    require(
      _sip.depositStatus[_monthId] == 0
      , 'cannot deposit again'
    );

    /// @dev calculating benefits to be given in future because of this deposit
    uint256 _benefitsToBeGiven = _depositAmount
      .mul(sipPlans[ _sip.planId ].monthlyBenefitFactor)
      .div(1000)
      .mul(sipPlans[ _sip.planId ].benefitPeriodYears);

    require(
      fundsDeposit >= _benefitsToBeGiven.add(pendingBenefitAmountOfAllStakers)
      , 'enough funds should be there in SIP'
    );

    /// @dev transfering staker tokens to SIP contract
    require(token.transferFrom(msg.sender, address(this), _depositAmount));

    /// @dev check if deposit is allowed according to current time
    uint256 _depositStatus = getDepositStatus(_stakerAddress, _sipId, _monthId);
    require(_depositStatus > 0, 'grace period elapsed or too early');

    /// @dev updating deposit status
    _sip.depositStatus[_monthId] = _depositStatus;

    /// @dev adding to total deposit in SIP
    _sip.totalDeposited = _sip.totalDeposited.add(_depositAmount);

    /// @dev adding to pending benefits
    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.add(
      _benefitsToBeGiven
    );

    emit NewDeposit(_stakerAddress, _sipId, _monthId, _depositAmount, _benefitsToBeGiven, msg.sender);
  }

  /// @notice this function is used to withdraw benefits.
  /// @dev withdraw can be done by any nominee of this SIP.
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker address portfolio.
  /// @param _withdrawlmonthId: withdraw month id starts from 1 upto as per plan.
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

    /// @dev updating pending benefits
    pendingBenefitAmountOfAllStakers = pendingBenefitAmountOfAllStakers.sub(_withdrawlAmount);

    /// @dev updating fundsDeposit
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

  /// @notice this functin is used to withdraw powerbooster
  /// @dev withdraw can be done by any nominee of this SIP.
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker address portfolio.
  function withdrawPowerBooster(
    address _stakerAddress,
    uint256 _sipId
  ) public meOrNominee(_stakerAddress, _sipId) {
    SIP storage _sip = sips[_stakerAddress][_sipId];

    /// @dev limiting only powerbooster withdrawls
    require(_sip.powerBoosterWithdrawls < 3, 'only 3 power boosters');
    uint256 _powerBoosterSerial = _sip.powerBoosterWithdrawls + 1;

    /// @dev not using SafeMath because uint256 range is safe
    uint256 _allowedTimestamp = _sip.stakingTimestamp
      + sipPlans[ _sip.planId ].accumulationPeriodMonths * EARTH_SECONDS_IN_MONTH
      + sipPlans[ _sip.planId ].benefitPeriodYears * 12 * EARTH_SECONDS_IN_MONTH * _powerBoosterSerial / 3 - EARTH_SECONDS_IN_MONTH;

    /// @dev opening window for nominee after sometime
    if(msg.sender != _stakerAddress) {
      if(_sip.appointeeVotes > _sip.numberOfAppointees.div(2)) {
        /// @dev with concensus of appointees, withdraw is allowed in 6 months
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 6;
      } else {
        /// @dev otherwise a default of 1 year delay in withdrawing benefits
        _allowedTimestamp += EARTH_SECONDS_IN_MONTH * 12;
      }
    }

    require(now > _allowedTimestamp, 'cannot withdraw early');

    /// @dev marking that power booster is withdrawn
    _sip.powerBoosterWithdrawls = _powerBoosterSerial;

    /// @dev calculating power booster amount
    uint256 _powerBoosterAmount = _sip.totalDeposited.div(3);

    /// @dev penalising power booster amount as per plan if commitment not met as per plan
    if(_powerBoosterSerial == 1) {
      uint256 _totalPenaltyFactor;
      for(uint256 i = 1; i <= sipPlans[ _sip.planId ].accumulationPeriodMonths; i++) {
        if(_sip.depositStatus[i] == 0) {
          /// @dev for defaulted months
          _totalPenaltyFactor += sipPlans[ _sip.planId ].defaultPenaltyFactor;
        } else if(_sip.depositStatus[i] == 1) {
          /// @dev for grace period months
          _totalPenaltyFactor += sipPlans[ _sip.planId ].gracePenaltyFactor;
        }
      }
      uint256 _penaltyAmount = _powerBoosterAmount.mul(_totalPenaltyFactor).div(1000);

      /// @dev allocate penalty amount into fund.
      fundsDeposit = fundsDeposit.add(_penaltyAmount);

      /// @dev subtracting penalty form power booster amount
      _powerBoosterAmount = _powerBoosterAmount.sub(_penaltyAmount);
    }

    /// @dev transfering tokens to wallet of withdrawer
    token.transfer(msg.sender, _powerBoosterAmount);

    emit PowerBoosterWithdrawl(
      _stakerAddress,
      _sipId,
      _powerBoosterSerial,
      _powerBoosterAmount,
      msg.sender
    );
  }

  /// @notice this function is used to update nominee status of a wallet address in SIP
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _nomineeAddress: eth wallet address of nominee.
  /// @param _newNomineeStatus: true or false, whether this should be a nominee or not.
  function toogleNominee(
    uint256 _sipId,
    address _nomineeAddress,
    bool _newNomineeStatus
  ) public {
    /// @dev updating nominee status
    sips[msg.sender][_sipId].nominees[_nomineeAddress] = _newNomineeStatus;

    /// @dev emiting event for UI and other applications
    emit NomineeUpdated(msg.sender, _sipId, _nomineeAddress, _newNomineeStatus);
  }

  /// @notice this function is used to update appointee status of a wallet address in SIP
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _appointeeAddress: eth wallet address of appointee.
  /// @param _newAppointeeStatus: true or false, should this have appointee rights or not.
  function toogleAppointee(
    uint256 _sipId,
    address _appointeeAddress,
    bool _newAppointeeStatus
  ) public {
    SIP storage _sip = sips[msg.sender][_sipId];

    /// @dev if not an appointee already and _newAppointeeStatus is true, adding appointee
    if(!_sip.appointees[_appointeeAddress] && _newAppointeeStatus) {
      _sip.numberOfAppointees = _sip.numberOfAppointees.add(1);
      _sip.nominees[_appointeeAddress] = true;
    }

    /// @dev if already an appointee and _newAppointeeStatus is false, removing appointee
    else if(_sip.appointees[_appointeeAddress] && !_newAppointeeStatus) {
      _sip.nominees[_appointeeAddress] = false;
      _sip.numberOfAppointees = _sip.numberOfAppointees.sub(1);
    }

    emit AppointeeUpdated(msg.sender, _sipId, _appointeeAddress, _newAppointeeStatus);
  }

  /// @notice this function is used by appointee to vote that nominees can withdraw early
  /// @dev need to be appointee, set by staker themselves
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  function appointeeVote(
    address _stakerAddress,
    uint256 _sipId
  ) public {
    SIP storage _sip = sips[_stakerAddress][_sipId];
    require(_sip.appointees[msg.sender]
      , 'should be appointee to cast vote'
    );

    /// @dev removing appointee's rights to vote again
    _sip.appointees[msg.sender] = false;

    /// @dev adding a vote to SIP
    _sip.appointeeVotes = _sip.appointeeVotes.add(1);

    emit AppointeeVoted(_stakerAddress, _sipId, msg.sender);
  }

  /// @notice this function is used to read all time deposit status of any staker SIP
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _monthId: deposit month id starts from 1 upto as per plan
  /// @return 0 => no deposit, 1 => grace deposit, 2 => on time deposit
  function getDepositDoneStatus(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _monthId
  ) public view returns (uint256) {
    return sips[_stakerAddress][_sipId].depositStatus[_monthId];
  }

  /// @notice this function is used to calculate deposit status according to current time
  /// @dev it is used in deposit function require statement.
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _monthId: deposit month id to calculate status for
  /// @return 0 => too late, 1 => its grace time, 2 => on time
  function getDepositStatus(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _monthId
  ) public view returns (uint256) {
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

  /// @notice this function is used to get avalilable withdrawls upto a withdrawl month id
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _withdrawlMonthId: withdrawl month id upto which to calculate returns for
  /// @param _isNomineeWithdrawing: different status in case of nominee withdrawl
  /// @return gives available withdrawl amount upto the withdrawl month id
  function getPendingWithdrawlAmount(
    address _stakerAddress,
    uint256 _sipId,
    uint256 _withdrawlMonthId,
    bool _isNomineeWithdrawing
  ) public view returns (uint256) {
    SIP storage _sip = sips[_stakerAddress][_sipId];

    /// @dev calculate allowed time for staker
    uint256 withdrawlAllowedTimestamp
      = _sip.stakingTimestamp
        + EARTH_SECONDS_IN_MONTH * (
          sipPlans[ _sip.planId ].accumulationPeriodMonths
            + _withdrawlMonthId - 1
        );

    /// @dev if nominee is withdrawing, update the allowed time
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

  /// @notice this function is used to view nomination
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _nomineeAddress: eth wallet address of nominee.
  /// @return tells whether this address is a nominee or not
  function viewNomination(
    address _stakerAddress,
    uint256 _sipId,
    address _nomineeAddress
  ) public view returns (bool) {
    return sips[_stakerAddress][_sipId].nominees[_nomineeAddress];
  }

  /// @notice this function is used to view appointation
  /// @param _stakerAddress: address of initiater of this SIP.
  /// @param _sipId: id of SIP in staker portfolio.
  /// @param _appointeeAddress: eth wallet address of apointee.
  /// @return tells whether this address is a appointee or not
  function viewAppointation(
    address _stakerAddress,
    uint256 _sipId,
    address _appointeeAddress
  ) public view returns (bool) {
    return sips[_stakerAddress][_sipId].appointees[_appointeeAddress];
  }
}

/// @dev For interface requirement
contract ERC20 {
  function transfer(address _to, uint256 _value) public returns (bool success);
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
}
