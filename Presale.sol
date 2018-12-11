pragma solidity ^0.4.24;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";
import "./BuratinoToken.sol";
import "./Crowdsale.sol";
import "./Ownable.sol";

contract Presale is Ownable, usingOraclize {

    using SafeMath for uint;

    address public multisig;
    uint256 public dollarsRaised;
    uint256 public tokensSaled;
    uint256 public startTime = 1533114001;
    uint256 public startPreICOTime = 1535749199;
    uint256 public endTime = 1538341199;
    BurCoin public token;
    Crowdsale public crowdsale;
    uint256 public saleSupply = 180000000 * 100000000;
    uint256 public presaleSupply = 21428573 * 100000000;
    uint256 public bountySupply = 750000 * 100000000;
    uint256 public rate = 700000000;
    uint256 public bonusMul = 20;
    uint256 public minAmount =        500000000000000000000;
    uint256 public minAmountPreICO =  500000000000000000000;
    uint256 public minAmountPreSale = 5000000000000000000000;
    uint256 public maxAmount =      24999000000000000000000;
    mapping(address => uint256) public oraclizeRefundBalances;
    mapping(address => uint256) public oraclizePrices;
    mapping(bytes32 => uint256) public investAmount;
    mapping(bytes32 => address) public investAddress;
    mapping(address => bool) public invested;
    
    event SetPrice(bytes32 _id, uint256 _price);

    modifier saleIsOn() {
        require(now > startTime && now < endTime);
        _;
    }

    modifier saleIsEnd() {
        require(now >= endTime);
        _;
    }

    constructor(address _multisig) public {
        multisig = _multisig;
        token = new BurCoin();
    }

    function startCrowdsale() saleIsEnd onlyOwner public {
        crowdsale = new Crowdsale(multisig, token, dollarsRaised, tokensSaled, saleSupply, bountySupply);
        token.transfer(address(crowdsale), token.balanceOf(this));
        token.transferOwnership(address(crowdsale));
        crowdsale.transferOwnership(owner);
    }
    
    function privateSaleStatus() public returns(bool success) {
        if (now > startPreICOTime && now < endTime) {
            minAmount = minAmountPreICO;
            bonusMul = 20;
            return true;
        } else if (now > startTime && now < endTime && presaleSupply > 14285715 * 100000000) {
            minAmount = minAmountPreSale;
            bonusMul = 30;
            return true;
        } else {
            return false;
        }
    }

    function pay() saleIsOn payable public {
        require(privateSaleStatus());
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
        if (dollarsInvest < minAmount || dollarsInvest > maxAmount) {
            investAddress[_myid].transfer(investAmountMem - oraclizePrices[investAddress[_myid]]);
            return;
        }
        dollarsRaised = dollarsRaised.add(dollarsInvest);
        uint256 tokens = dollarsInvest.div(rate);
        if (tokensSaled + tokens > presaleSupply) {
            investAddress[_myid].transfer(investAmountMem - oraclizePrices[investAddress[_myid]]);
            return;
        }
        createTokens(tokens, investAddress[_myid]);
    }

    function createTokens(uint256 _tokens, address _sender) saleIsOn private {
        uint256 bonus = _tokens.div(100).mul(bonusMul);
        uint256 tokens = _tokens.add(bonus);
        require(presaleSupply >= _tokens);
        saleSupply = saleSupply.sub(_tokens);
        presaleSupply = presaleSupply.sub(_tokens);
        tokensSaled = tokensSaled.add(_tokens);
        token.transfer(_sender, tokens);
    }

    function adminSendTokens(address _to, uint256 _value, uint256 _valueWithBonus, uint256 _dollarsAmount) onlyOwner public returns(bool) {
        require(saleSupply >= _value);
        saleSupply = saleSupply.sub(_value);
        presaleSupply = presaleSupply.sub(_value);
        dollarsRaised = dollarsRaised.add(_dollarsAmount);
        return token.transfer(_to, _valueWithBonus);
    }

    function adminRefundTokens(address _from, uint256 _value, uint256 _valueWithBonus, uint256 _dollarsAmount) onlyOwner public returns(bool) {
        saleSupply = saleSupply.add(_value);
        presaleSupply = presaleSupply.add(_value);
        dollarsRaised = dollarsRaised.sub(_dollarsAmount);
        return token.refund(_from, _valueWithBonus);
    }

    function bountySend(address _to, uint256 _value) saleIsOn onlyOwner public returns(bool) {
        require(bountySupply >= _value);
        bountySupply = bountySupply.sub(_value);
        return token.transfer(_to, _value);
    }

    function bountyRefund(address _from, uint256 _value) saleIsOn onlyOwner public returns(bool) {
        bountySupply = bountySupply.add(_value);
        return token.refund(_from, _value);
    }

    function refundOraclizeNotResponse() public returns(bool) {
        require(invested[msg.sender]);
        uint256 value = oraclizeRefundBalances[msg.sender];
        oraclizeRefundBalances[msg.sender] = 0;
        invested[msg.sender] = false;
        msg.sender.transfer(value);
    }

    function forwardFunds() onlyOwner public {
        multisig.transfer(address(this).balance);
    }

    function setMultisig(address _multisig) onlyOwner public {
        multisig = _multisig;
    }

    function() external payable {
        pay();
    }

}
