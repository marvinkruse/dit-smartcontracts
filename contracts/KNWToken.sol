pragma solidity ^0.4.25;

import "./libraries/SafeMath.sol";

contract KNWToken {
    using SafeMath for uint256;

    event Mint(address indexed who, string label, uint256 value);
    event Burn(address indexed who, string label, uint256 value);

    mapping (address => mapping (string => uint256)) private _balances;
    mapping (address => mapping (string => uint256)) private _lockedTokens;
    mapping (address => mapping (uint256 => string)) private _labels;
    mapping (address => uint256) private _labelCount;

    uint256 private _totalSupply;
    mapping (string => uint256) private _labelSupply;
    
    string constant public symbol = "KNW";
    string constant public name = "Knowledge Token";
    uint8 constant public decimals = 18;

    address public votingAddress;

    function setVotingAddress(address _newVotingAddress) external {
        require(_newVotingAddress != address(0) && votingAddress == address(0), "KNWVoting address can only be set if it's not empty and hasn't already been set");
        votingAddress = _newVotingAddress;
    }
    
    // Returns the total KNW count (all labels)
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    // Returns the KNW count of a single label
    function totalLabelSupply(string memory _label) public view returns (uint256) {
        return _labelSupply[_label];
    }

    // Returns the KNW balance of a label at an address
    function balanceOfLabel(address _address, string memory _label) public view returns (uint256) {
        return _balances[_address][_label];
    }

    // Returns the free (non-locked) KNW balance of a label at an address 
    function freeBalanceOfLabel(address _address, string memory _label) public view returns (uint256) {
        return _balances[_address][_label].sub(_lockedTokens[_address][_label]);
    }

    // Returns the labels of an address and its label id
    function labelOfAddress(address _address, uint256 _labelID) public view returns (string memory) {
        return _labels[_address][_labelID];
    }

    // Returns the id of labels of an address
    function labelCountOfAddress(address _address) public view returns (uint256) {
        return _labelCount[_address];
    }

    // Locks and returns the free tokens of a label at an address
    function lockTokens(address _address, string memory _label) public returns (uint256 numberOfTokens) {
        require(msg.sender == votingAddress, "Only the KNWVoting contract is allowed to call this");
        numberOfTokens = 0;
        if(_balances[_address][_label] > _lockedTokens[_address][_label]) {
            numberOfTokens = _balances[_address][_label].sub(_lockedTokens[_address][_label]);
            _lockedTokens[_address][_label] = _lockedTokens[_address][_label].add(numberOfTokens);
        }
        return numberOfTokens;
    }

    // Unlocks the specified amount of tokens (used after a vote is resolved)
    function unlockTokens(address _address, string _label, uint256 _numberOfTokens) public {
        require(msg.sender == votingAddress, "Only the KNWVoting contract is allowed to call this");
        require(_lockedTokens[_address][_label] <= _balances[_address][_label], "Cant lock more KNW than an address has");
        _lockedTokens[_address][_label] = _lockedTokens[_address][_label].sub(_numberOfTokens);
    }

    // Mints new tokens according to the specified minting method and the winning percentage
    function mint(address _address, string _label, uint256 _winningPercentage, uint256 _mintingMethod) external {
        require(msg.sender == votingAddress, "Only the KNWVoting contract is allowed to call this");
        require(_address != address(0), "Address can't be empty");
        require(bytes(_label).length > 0, "Knowledge-Label can't be empty");

        uint256 mintedKNW = 0;
        if(_mintingMethod == 0) {
            // Regular minting:
            // For votes ending near 100% about 1 KNW will be minted
            // For votes ending near 50% about 0,0002 KNW will be minted 
            mintedKNW = _winningPercentage.sub(50).mul(20000000000000000);
        }

        _totalSupply = _totalSupply.add(mintedKNW);
        _labelSupply[_label] = _labelSupply[_label].add(mintedKNW);
        
        // If the address doesn't have a balance for this label the label will be added to the list
        if(_balances[_address][_label] == 0) {
            _labelCount[_address] = _labelCount[_address].add(1);
            _labels[_address][_labelCount[_address]] = _label;
        }
        _balances[_address][_label] = _balances[_address][_label].add(mintedKNW);

        emit Mint(_address, _label, mintedKNW);
    }

    // Burns tokens accoring to the specified burning method and the winning percentage
    function burn(address _address, string _label, uint256 _stakedTokens, uint256 _winningPercentage, uint256 _burningMethod) external {
        require(msg.sender == votingAddress, "Only the KNWVoting contract is allowed to call this");
        require(_address != address(0), "Address can't be empty");
        require(bytes(_label).length > 0, "Knowledge-Label can't be empty");
        require(_balances[_address][_label] >= _stakedTokens, "Can't burn more KNW than the address holds");

        uint256 burnedTokens = _stakedTokens;
        if(_stakedTokens > 0) {
            if(_burningMethod == 0) {
                // Method 1: square-root based
                uint256 deductedKnwBalance = ((_stakedTokens.div(10**12)).sqrt()).mul(10**15);
                if(deductedKnwBalance < _stakedTokens) {
                    burnedTokens = burnedTokens.sub(deductedKnwBalance);
                } else {
                    // For balances < 1 (10^18) the sqaure-root would be bigger than the balance due to the nature of square-roots.
                    // So for balances <= 1 half of the balance will be burned
                    burnedTokens = burnedTokens.div(2);
                }
            } else if(_burningMethod == 1) {
                // Method 2: each time the token balance will be divded by 2
                burnedTokens = burnedTokens.div(2);
            } else if(_burningMethod == 2) {
                // Method 3: 
                // For votes ending near 100% nearly 100% of the balance will be burned
                // For votes ending near 50% nearly 0% of the balance will be burned 
                uint256 burningPercentage = (_winningPercentage.mul(2)).sub(100);
                burnedTokens = (burnedTokens.mul(burningPercentage)).div(100);
            }
            _totalSupply = _totalSupply.sub(burnedTokens);
            _labelSupply[_label] = _labelSupply[_label].sub(burnedTokens);
            _balances[_address][_label] = _balances[_address][_label].sub(burnedTokens);
            emit Burn(_address, _label, burnedTokens);
        }
    }
}