// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ReentrancyGuard {
    bool private _nonReentrant;
    constructor() { _nonReentrant = false; }
    modifier nonReentrant() {
        require(!_nonReentrant, "ReentrancyGuard: reentrant call");
        _nonReentrant = true;
        _;
        _nonReentrant = false;
    }
}
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), _owner); }
    modifier onlyOwner() { require(_owner == msg.sender, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract GaslessRelayer is ReentrancyGuard, Ownable {
    struct RelayRequest {
        address from;
        address to;
        uint256 value;
        bytes data;
        uint256 nonce;
        uint256 deadline;
        bool executed;
    }
    mapping(uint256 => RelayRequest) public requests;
    mapping(address => uint256) public nonces;
    uint256 public requestCount;
    uint256 public totalRelayed;
    uint256 public relayerFee;

    event RelayExecuted(uint256 indexed rid, address indexed from, address indexed to, uint256 value);
    event FeeUpdated(uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    function setRelayerFee(uint256 fee) external onlyOwner { relayerFee = fee; }

    // FIX: relay now verifies an ECDSA signature from msg.sender authorizing the relay,
    // deducts relayerFee from the forwarded value, and the fee is withdrawable by the owner.
    function relay(address to, uint256 value, bytes calldata data, uint256 deadline, bytes calldata signature)
        external payable nonReentrant returns (uint256) {
        require(deadline > block.timestamp, "Expired");
        require(value >= relayerFee, "Value below fee");
        uint256 nonce = nonces[msg.sender]++;
        uint256 rid = requestCount + 1;
        requestCount = rid;
        // signature over (rid, from, to, value, data, nonce, deadline)
        bytes32 hash = keccak256(abi.encode(rid, msg.sender, to, value, data, nonce, deadline));
        require(ecrecover(hash, uint8(signature[64]), bytes32(signature[:32]), bytes32(signature[32:64])) == msg.sender, "Invalid signature");
        totalRelayed += value;
        requests[rid] = RelayRequest({from: msg.sender, to: to, value: value, data: data, nonce: nonce, deadline: deadline, executed: false});
        uint256 netValue = value - relayerFee;
        (bool success,) = to.call{value: netValue}(data);
        require(success, "Relay call failed");
        requests[rid].executed = true;
        emit RelayExecuted(rid, msg.sender, to, value);
        return rid;
    }

    // FIX: relayerFee was set but never collected — owner can now withdraw accumulated fees.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 fees = address(this).balance;
        require(fees > 0, "No fees to withdraw");
        (bool ok,) = payable(owner()).call{value: fees}("");
        require(ok, "ETH transfer failed");
        emit FeesWithdrawn(owner(), fees);
    }

    function getRequest(uint256 rid) external view returns (address from, address to, uint256 value, bytes memory data, uint256 nonce, uint256 deadline, bool executed) {
        RelayRequest storage r = requests[rid];
        return (r.from, r.to, r.value, r.data, r.nonce, r.deadline, r.executed);
    }
}
