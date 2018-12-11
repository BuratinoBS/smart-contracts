pragma solidity ^0.4.24;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";
import "./BuratinoToken.sol";
import "./Ownable.sol";

contract Crowdsale is Ownable, usingOraclize {

    using SafeMath for uint;

    address public multisig;
    uint256 public rate = 1000000000;
    uint256 public dollarsRaised;
    uint256 public tokensSaled;
    uint256 public hardcap = 18000000000000000000000000;
    uint256 public softcap =  3000000000000000000000000;
    uint256 public startTime = 1538341211;
    uint256 public endTime = 1541019599;
    uint256 public minAmount =   100000000000000000000;
    uint256 public maxAmount = 24999000000000000000000;
    BurCoin public token;
    uint256 public saleSupply;
    uint256 public bountySupply;
    bool public sendToTeam;
    bool public saleStopped;
    mapping(address => uint256) public saleBalances;
    mapping(address => uint256) public oraclizeRefundBalances;
    mapping(address => uint256) public oraclizePrices;
    mapping(bytes32 => uint256) public investAmount;
    mapping(bytes32 => address) public investAddress;
    mapping(address => bool) public invested;

    uint256 public constant RESERVED_SUPPLY = 17500000 * 100000000;

    event SetPrice(bytes32 _id, uint256 _price);

    constructor(address _multisig, BurCoin _token, uint256 _dollarsRaised, uint256 _tokensSaled,
                        uint256 _saleSupply, uint256 _bountySupply) public {
        multisig = _multisig;
        token = _token;
        dollarsRaised = _dollarsRaised;
        tokensSaled = _tokensSaled;
        saleSupply = _saleSupply;
        bountySupply = _bountySupply;
    }

    modifier isOverSoftcap() {
        require(dollarsRaised >= softcap);
        _;
    }

    modifier isUnderSoftcap() {
        require(dollarsRaised < softcap);
        _;
    }

    modifier saleIsOn() {
        require(now > startTime && now < endTime);
        _;
    }

    modifier saleIsEnd() {
        require(now >= endTime);
        _;
    }

    modifier saleNoStopped() {
        require(saleStopped == false);
        _;
    }

    function stopSale() onlyOwner saleIsEnd isOverSoftcap public returns(bool) {
        if (saleSupply > 0) {
            token.burn(saleSupply);
            saleSupply = 0;
        }
        saleStopped = true;
        token.stopSale();
        token.transferOwnership(msg.sender);
    }

    function pay() saleIsOn saleNoStopped payable public {
        uint256 weiAmount = msg.value;
        oraclizePrices[msg.sender] = oraclize_getPrice('URL');
        require(oraclizePrices[msg.sender] < weiAmount);
        require(invested[msg.sender] == false);
        oraclizeRefundBalances[msg.sender] = weiAmount;
        invested[msg.sender] = true;
        bytes32 senderId = oraclize_query("URL","json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD");
        investAmount[senderId] = weiAmount;
        investAddress[senderId] = msg.sender;
    }

    function __callback(bytes32 _myid, string _result) public {
        require(msg.sender == oraclize_cbAddress());
        require(invested[investAddress[_myid]]);
        invested[investAddress[_myid]] = false;
        uint256 investAmountMem = investAmount[_myid];
        investAmount[_myid] = 0;
        uint256 price = parseInt(_result);
        emit SetPrice(_myid, price);
        if (price == 0) {
            investAddress[_myid].transfer(investAmountMem - oraclizePrices[investAddress[_myid]]);
            return;
        }
        uint256 dollarsInvest = investAmountMem.mul(price);
        if (dollarsInvest < minAmount || dollarsInvest > maxAmount || dollarsRaised + dollarsInvest > hardcap) {
            investAddress[_myid].transfer(investAmountMem - oraclizePrices[investAddress[_myid]]);
            return;
        }
        dollarsRaised = dollarsRaised.add(dollarsInvest);
        uint256 tokens = dollarsInvest.div(rate);
        if (tokensSaled + tokens > saleSupply) {
            investAddress[_myid].transfer(investAmountMem - oraclizePrices[investAddress[_myid]]);
            return;
        }
        createTokens(investAmountMem, tokens, investAddress[_myid]);
    }

    function createTokens(uint256 _weiAmount, uint256 _tokens, address _sender) saleIsOn public {
        uint256 bonus = 0;
        uint256 fullPercent = 100 * 1 ether;
        uint256 percent = 0;
        if (now < endTime - 3 weeks) {
            bonus = _tokens.div(100).mul(10);
        } else if (now > endTime - 3 weeks && now < endTime - 2 weeks) {
            percent = 7500000000000000000;
            bonus = _tokens.mul(1 ether).div(fullPercent).mul(percent).div(1 ether);
        } else if (now > endTime - 2 weeks && now < endTime - 1 weeks) {
            bonus = _tokens.div(100).mul(5);
        } else {
            percent = 2500000000000000000;
            bonus = _tokens.mul(1 ether).div(fullPercent).mul(percent).div(1 ether);
        }
        uint256 tokens = _tokens.add(bonus);
        require(saleSupply >= _tokens);
        saleSupply = saleSupply.sub(_tokens);
        tokensSaled = tokensSaled.add(_tokens);
        saleBalances[_sender] = saleBalances[_sender].add(_weiAmount - oraclizePrices[_sender]);
        token.transfer(_sender, tokens);
    }

    function adminSendTokens(address _to, uint256 _value, uint256 _valueWithBonus, uint256 _dollarsAmount) onlyOwner saleNoStopped public returns(bool) {
        require(saleSupply >= _value);
        saleSupply = saleSupply.sub(_value);
        dollarsRaised = dollarsRaised.add(_dollarsAmount);
        return token.transfer(_to, _valueWithBonus);
    }

    function adminRefundTokens(address _from, uint256 _value, uint256 _valueWithBonus, uint256 _dollarsAmount) onlyOwner saleNoStopped public returns(bool) {
        saleSupply = saleSupply.add(_value);
        dollarsRaised = dollarsRaised.sub(_dollarsAmount);
        return token.refund(_from, _valueWithBonus);
    }

    function bountySend(address _to, uint256 _value) onlyOwner saleNoStopped public returns(bool) {
        require(bountySupply >= _value);
        bountySupply = bountySupply.sub(_value);
        return token.transfer(_to, _value);
    }

    function bountyRefund(address _from, uint256 _value) onlyOwner saleNoStopped public returns(bool) {
        bountySupply = bountySupply.add(_value);
        return token.refund(_from, _value);
    }

    function refund() saleIsEnd isUnderSoftcap public returns(bool) {
        uint256 value = saleBalances[msg.sender];
        saleBalances[msg.sender] = 0;
        msg.sender.transfer(value);
    }

    function refundOraclizeNotResponse() public returns(bool) {
        require(invested[msg.sender]);
        uint256 value = oraclizeRefundBalances[msg.sender];
        oraclizeRefundBalances[msg.sender] = 0;
        invested[msg.sender] = false;
        msg.sender.transfer(value);
    }

    function refundTeamTokens() saleIsEnd onlyOwner public returns(bool) {
        require(sendToTeam == false);
        sendToTeam = true;
        return token.transfer(msg.sender, RESERVED_SUPPLY);
    }

    function forwardFunds() onlyOwner isOverSoftcap public {
        multisig.transfer(address(this).balance);
    }

    function setMultisig(address _multisig) onlyOwner public {
        multisig = _multisig;
    }

    function() external payable {
        pay();
    }

}
