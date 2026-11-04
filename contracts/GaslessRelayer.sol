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
    struct RelayRequest { address from;address to;uint256 value;bytes data;uint256 nonce;uint256 deadline;bool executed; }
    mapping(uint256=>RelayRequest) public requests;mapping(address=>uint256) public nonces;uint256 public requestCount;uint256 public totalRelayed;uint256 public relayerFee;
    event RelayExecuted(uint256 indexed rid,address indexed from,address indexed to,uint256 value);event FeeUpdated(uint256 newFee);event FeesWithdrawn(address indexed to,uint256 amount);
    function setRelayerFee(uint256 fee) external onlyOwner { relayerFee=fee;emit FeeUpdated(fee); }
    function getRelayHash(address from,address to,uint256 value,bytes calldata data,uint256 deadline) public view returns(bytes32) { return keccak256(abi.encode(block.chainid,address(this),from,to,value,keccak256(data),nonces[from],deadline)); }
    function relay(address to,uint256 value,bytes calldata data,uint256 deadline,bytes calldata signature) external payable nonReentrant returns(uint256) { return _relay(msg.sender,to,value,data,deadline,signature); }
    function relayFor(address from,address to,uint256 value,bytes calldata data,uint256 deadline,bytes calldata signature) external payable nonReentrant returns(uint256) { return _relay(from,to,value,data,deadline,signature); }
    function _relay(address from,address to,uint256 value,bytes calldata data,uint256 deadline,bytes calldata signature) private returns(uint256 rid) {
        require(from!=address(0)&&to!=address(0)&&to!=address(this),"Invalid parties");require(deadline>block.timestamp,"Expired");require(msg.value==value&&value>=relayerFee,"Payment mismatch");require(signature.length==65,"Invalid signature length");require(uint256(bytes32(signature[32:64]))<=0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0,"Invalid signature s");uint8 v=uint8(signature[64]);require(v==27||v==28,"Invalid signature v");bytes32 raw=getRelayHash(from,to,value,data,deadline);bytes32 digest=keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32",raw));require(ecrecover(digest,v,bytes32(signature[:32]),bytes32(signature[32:64]))==from,"Invalid signature");uint256 nonce=nonces[from]++;rid=++requestCount;requests[rid]=RelayRequest(from,to,value,data,nonce,deadline,false);(bool ok,)=to.call{value:value-relayerFee}(data);require(ok,"Relay call failed");requests[rid].executed=true;totalRelayed+=value;emit RelayExecuted(rid,from,to,value);
    }
    function withdrawFees() external onlyOwner nonReentrant { uint256 amount=address(this).balance;require(amount>0,"No fees");(bool ok,)=owner().call{value:amount}("");require(ok,"Withdraw failed");emit FeesWithdrawn(owner(),amount); }
    function getRequest(uint256 rid) external view returns(address from,address to,uint256 value,bytes memory data,uint256 nonce,uint256 deadline,bool executed) { RelayRequest storage r=requests[rid];return(r.from,r.to,r.value,r.data,r.nonce,r.deadline,r.executed); }
}

