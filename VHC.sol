pragma solidity ^0.4.24;

import "github.com/OpenZeppelin/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "github.com/OpenZeppelin/openzeppelin-solidity/contracts/AddressUtils.sol";

/**
 * @title MultiOwnable
 */
contract MultiOwnable {
    address public root;
    mapping (address => bool) public owners;
    
    constructor() public {
        root = msg.sender;
        owners[root] = true;
    }
    
    modifier onlyOwner() {
        require(owners[msg.sender]);
        _;
    }
    
    modifier onlyRoot() {
        require(msg.sender == root);
        _;
    }
    
    function newOwner(address owner) onlyRoot public returns (bool) {
        require(owner != address(0));
        
        owners[owner] = true;
        return true;
    }
    
    function deleteOwner(address owner) onlyRoot public returns (bool) {
        require(owner != root);
        
        delete owners[owner];
        return true;
    }
}

/**
 * @title Lockable token
 **/
contract LockableToken is StandardToken, MultiOwnable {
    bool public locked = true;
    uint256 public constant LOCK_MAX = uint256(-1);
    
    /**
     * @dev 락 상태에서도 거래 가능한 언락 계정
     */
    mapping(address => bool) public unlockAddrs;
    
    /**
     * @dev 계정 별로 lock value 만큼 잔고가 잠김
     * @dev - 값이 0 일 때 : 잔고가 0 이어도 되므로 제한이 없는 것임.
     * @dev - 값이 LOCK_MAX 일 때 : 잔고가 uint256 의 최대값이므로 아예 잠긴 것임.
     */
    mapping(address => uint256) public lockValues;
    
    event Locked(bool locked, string note);
    event LockedTo(address indexed addr, bool locked, string note);
    event SetLockValue(address indexed addr, uint256 value, string note);
    
    constructor() public {
        unlockTo(msg.sender, "");
    }
    
    modifier checkUnlock (address addr, uint256 value) {
        require(!locked || unlockAddrs[addr]);
        require(balances[addr].sub(value) >= lockValues[addr]);
        _;
    }
    
    function lock(string note) onlyOwner public {
        locked = true;  
        emit Locked(locked, note);
    }
    
    function unlock(string note) onlyOwner public {
        locked = false;
        emit Locked(locked, note);
    }
    
    function lockTo(address addr, string note) onlyOwner public {
        require(addr != root);
        
        setLockValue(addr, LOCK_MAX, note);
        unlockAddrs[addr] = false;
        
        emit LockedTo(addr, true, note);
    }
    
    function unlockTo(address addr, string note) onlyOwner public {
        if (lockValues[addr] == LOCK_MAX)
            setLockValue(addr, 0, note);
        unlockAddrs[addr] = true;
        
        emit LockedTo(addr, false, note);
    }
    
    function setLockValue(address addr, uint256 value, string note) onlyOwner public {
        lockValues[addr] = value;
        emit SetLockValue(addr, value, note);
    }
    
    /**
     * @dev 이체 가능 금액을 조회한다.
     */ 
    function getMyUnlockValue() public view returns (uint256) {
        address addr = msg.sender;
        if ((!locked || unlockAddrs[addr]) && balances[addr] >= lockValues[addr])
            return balances[addr].sub(lockValues[addr]);
        else
            return 0;
    }
    
    function transfer(address to, uint256 value) checkUnlock(msg.sender, value) public returns (bool) {
        return super.transfer(to, value);
    }
    
    function transferFrom(address from, address to, uint256 value) checkUnlock(from, value) public returns (bool) {
        return super.transferFrom(from, to, value);
    }
}

/**
 * @title VHCBaseToken
 */
contract VHCBaseToken is LockableToken {
    using AddressUtils for address;
    
    event VHCTransfer(address indexed from, address indexed to, uint256 value, string note);
    event VHCTransferFrom(address indexed owner, address indexed spender, address indexed to, uint256 value, string note);
    event VHCApproval(address indexed owner, address indexed spender, uint256 value, string note);
    
    event VHCBurnFrom(address indexed controller, address indexed from, uint256 value, string note);

    // ERC20 함수들을 오버라이딩하여 super 로 올라가지 않고 무조건 vhc~ 함수로 지나가게 한다.
    function transfer(address to, uint256 value) public returns (bool ret) {
        return vhcTransfer(to, value, "");
    }
    
    function vhcTransfer(address to, uint256 value, string note) public returns (bool ret) {
        require(to != address(this));
        
        ret = super.transfer(to, value);
        emit VHCTransfer(msg.sender, to, value, note);
    }
    
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        return vhcTransferFrom(from, to, value, "");
    }
    
    function vhcTransferFrom(address from, address to, uint256 value, string note) public returns (bool ret) {
        require(to != address(this));
        
        ret = super.transferFrom(from, to, value);
        emit VHCTransferFrom(from, msg.sender, to, value, note);
    }

    function approve(address spender, uint256 value) public returns (bool) {
        return vhcApprove(spender, value, "");
    }
    
    function vhcApprove(address spender, uint256 value, string note) public returns (bool ret) {
        ret = super.approve(spender, value);
        emit VHCApproval(msg.sender, spender, value, note);
    }

    function increaseApproval(address spender, uint256 addedValue) public returns (bool) {
        return vhcIncreaseApproval(spender, addedValue, "");
    }

    function vhcIncreaseApproval(address spender, uint256 addedValue, string note) public returns (bool ret) {
        ret = super.increaseApproval(spender, addedValue);
        emit VHCApproval(msg.sender, spender, allowed[msg.sender][spender], note);
    }

    function decreaseApproval(address spender, uint256 subtractedValue) public returns (bool) {
        return vhcDecreaseApproval(spender, subtractedValue, "");
    }

    function vhcDecreaseApproval(address spender, uint256 subtractedValue, string note) public returns (bool ret) {
        ret = super.decreaseApproval(spender, subtractedValue);
        emit VHCApproval(msg.sender, spender, allowed[msg.sender][spender], note);
    }

    /**
     * @dev 화폐 소각. 반드시 이유를 메모로 남겨라.
     */
    function burnFrom(address from, uint256 value) internal returns (bool) {
        require(value <= balances[from]);
        
        balances[from] = balances[from].sub(value);
        totalSupply_ = totalSupply_.sub(value);
        
        emit Transfer(from, address(0), value);
        return true;        
    }
    
    function vhcBurnFrom(address from, uint256 value, string note) onlyOwner public returns (bool ret) {
        ret = burnFrom(from, value);
        emit VHCBurnFrom(msg.sender, from, value, note);
    }

    function destroy() onlyRoot public {
        selfdestruct(root);
    }
}

/**
 * @title VHCToken
 */
contract VHCToken is VHCBaseToken {
    using AddressUtils for address;
    
    string public constant name = "VHC";
    string public constant symbol = "VHC";
    uint8 public constant decimals = 18;
    
    uint256 public constant INITIAL_SUPPLY = 5e8 * (10 ** uint256(decimals));
    
    bytes4 internal constant VHC_RECEIVED = 0x8f935aff; // VHCTokenReceiver.onVHCTokenReceived.selector
    
    constructor() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
    }
    
    function vhcTransfer(address to, uint256 value, string note) public returns (bool ret) {
        ret = super.vhcTransfer(to, value, note);
        require(postTransfer(msg.sender, msg.sender, to, value, VHCReceiver.VHCReceiveType.VHC_TRANSFER));
    }
    
    function vhcTransferFrom(address from, address to, uint256 value, string note) public returns (bool ret) {
        ret = super.vhcTransferFrom(from, to, value, note);
        require(postTransfer(from, msg.sender, to, value, VHCReceiver.VHCReceiveType.VHC_TRANSFER));
    }
    
    function vhcBurnFrom(address from, uint256 value, string note) onlyOwner public returns (bool ret) {
        ret = super.vhcBurnFrom(from, value, note);
        require(postTransfer(0x0, msg.sender, from, value, VHCReceiver.VHCReceiveType.VHC_BURN));
    }
    
    function postTransfer(address owner, address spender, address to, uint256 value, VHCReceiver.VHCReceiveType receiveType) internal returns (bool) {
        if (!to.isContract())
            return true;
        
        bytes4 retval = VHCReceiver(to).onVHCReceived(owner, spender, value, receiveType);
        return (retval == VHC_RECEIVED);
    }
}


/**
 * @title VHCToken Receiver
 */ 
contract VHCReceiver {
    bytes4 internal constant VHC_RECEIVED = 0x8f935aff; // this.onVHCReceived.selector
    enum VHCReceiveType { VHC_TRANSFER, VHC_BURN }
    
    function onVHCReceived(address owner, address spender, uint256 value, VHCReceiveType receiveType) public returns (bytes4);
}

/**
 * @title VHCDappSample 
 */
contract VHCDappSample is VHCReceiver {
    event LogOnReceiveVHC(string message, address indexed owner, address indexed spender, uint256 value, VHCReceiveType receiveType);
    
    function onVHCReceived(address owner, address spender, uint256 value, VHCReceiveType receiveType) public returns (bytes4) {
        emit LogOnReceiveVHC("I receive VHCToken.", owner, spender, value, receiveType);
        
        return VHC_RECEIVED; // must return this value if successful
    }
}


