pragma solidity 0.4.25;

import "./libraries/SafeMath.sol";

interface KNWTokenContract {
    function addVotingContract(address _newContractAddress) external;
}

interface KNWVotingContract {
    function setCoordinatorAddress(address _newCoordinatorAddress) external;
    function setTokenAddress(address _newKNWTokenAddress) external;
    function addNewRepository(bytes32 _newRepository, uint256 _majority) external;
    function startVote(bytes32 _repository, address _address, string _knowledgeLabel, uint256 _commitDuration, uint256 _revealDuration, uint256 _proposersStake) external returns (uint256 voteID);
    function commitVote(uint256 _voteID, address _address, bytes32 _secretHash) external returns (uint256 numVotes);
    function openVote(uint256 _voteID, address _address, uint256 _voteOption, uint256 _salt) external;
    function endVote(uint256 _voteID) external returns (bool votePassed);
    function finalizeVote(uint256 _voteID, uint256 _voteOption, address _address) external view returns (uint256 reward);
}

/**
 * @title ditCoordinator
 *
 * @dev Implementation of the ditCoordinator contract, managing dit-enabled
 * repositories. This contract is the point of interaction of the user with
 * the ditCraft ecosystem, as the whole voting process is handled from here.
 */
contract ditCoordinator {
    using SafeMath for uint256;
    
    struct ditRepository {
        string[3] knowledgeLabels;
        uint256 currentProposalID;
        uint256 votingMajority;
    }

    struct commitProposal {
        uint256 KNWVoteID;
        string knowledgeLabel;
        address proposer;
        bool isFinalized;
        bool proposalAccepted;
        uint256 individualStake;
        uint256 totalStake;
        mapping (address => voterDetails) participantDetails;
    }

    struct voterDetails {
        uint256 numberOfVotes;
        uint256 choice;
        bool hasFinalized;
    }

    address public KNWVotingAddress;
    address public KNWTokenAddress;

    address public lastDitCoordinator;
    address public nextDitCoordinator;

    address internal ditManager;

    KNWVotingContract KNWVote;
    KNWTokenContract KNWToken;

    uint256 constant public MIN_VOTE_DURATION = 10*60; // 10 minutes
    uint256 constant public MAX_VOTE_DURATION = 2*7*24*60*60; // 2 weeks
    uint256 constant public MIN_OPEN_DURATION = 10*60; // 10 minutes
    uint256 constant public MAX_OPEN_DURATION = 2*7*24*60*60; // 2 weeks

    uint256 constant public MINTING_METHOD = 0;
    uint256 constant public BURNING_METHOD = 0;

    mapping (bytes32 => ditRepository) public repositories;
    mapping (bytes32 => mapping(uint256 => commitProposal)) public proposalsOfRepository;
    mapping (address => bool) public passedKYC;
    mapping (address => bool) public isKYCValidator;

    event ProposeCommit(bytes32 indexed repository, uint256 indexed proposal, address indexed who, string label);
    event CommitVote(bytes32 indexed repository, uint256 indexed proposal, address indexed who, string label, uint256 stake, uint256 numberOfVotes);
    event OpenVote(bytes32 indexed repository, uint256 indexed proposal, address indexed who, string label, bool accept, uint256 numberOfVotes);
    event FinalizeVote(bytes32 indexed repository, uint256 indexed proposal, string label, bool accepted);

    constructor(address _KNWTokenAddress, address _KNWVotingAddress, address _lastDitCoordinator) public {
        require(_KNWVotingAddress != address(0) && _KNWTokenAddress != address(0), "KNWVoting and KNWToken address can't be empty");
        KNWVotingAddress = _KNWVotingAddress;
        KNWVote = KNWVotingContract(KNWVotingAddress);
        KNWTokenAddress = _KNWTokenAddress;
        KNWToken = KNWTokenContract(KNWTokenAddress);

        lastDitCoordinator = _lastDitCoordinator;

        isKYCValidator[msg.sender] = true;
        ditManager = msg.sender;
    }

    function upgradeContract(address _address) public {
        require(msg.sender == ditManager);
        require(_address != address(0));
        nextDitCoordinator = _address;
    }

    function replaceDitManager(address _newManager) public {
        require(msg.sender == ditManager);
        require(_newManager != address(0));
        ditManager = _newManager;
    }

    function passKYC(address _address) public onlyKYCValidator(msg.sender) {
        passedKYC[_address] = true;
    }

    function revokeKYC(address _address) public onlyKYCValidator(msg.sender) {
        passedKYC[_address] = false;
    }

    function addKYCValidator(address _address) public onlyKYCValidator(msg.sender) {
        isKYCValidator[_address] = true;
    }

    function removeKYCValidator(address _address) public onlyKYCValidator(msg.sender) {
        isKYCValidator[_address] = false;
    }

    /**
     * @dev Creats a new ditCraft-based repository
     * @param _repository The descriptor of the repository (e.g. keccak256("github.com/example_repo"))
     * @param _label1 The first knowledge label of this repository (see KNWToken)
     * @param _label2 The second knowledge label of this repository (see KNWToken)
     * @param _label3 The third knowledge label of this repository (see KNWToken)
     * @param _votingMajority The majority needed for a vote to succeed 
     * @return True on success
     */
    function initRepository(bytes32 _repository, string _label1, string _label2, string _label3, uint256 _votingMajority) external onlyPassedKYC(msg.sender) returns (bool) {
        require(_repository != 0, "Repository descriptor can't be zero");
        require(repositories[_repository].votingMajority == 0, "Repository can only be initialized once");
        require(_votingMajority >= 50, "Voting majority has to be >= 50");
        require(bytes(_label1).length > 0 || bytes(_label2).length > 0 || bytes(_label3).length > 0, "Provide at least one Knowledge Label");
        require(nextDitCoordinator == address(0), "There is a newer contract deployed");

        // Storing the new dit-based repository
        repositories[_repository] = ditRepository({
            knowledgeLabels: [_label1, _label2, _label3],
            currentProposalID: 0,
            votingMajority: _votingMajority
        });

        KNWVote.addNewRepository(_repository, _votingMajority);
        
        return true;
    }

    function migrateRepository(bytes32 _repository) external onlyPassedKYC(msg.sender) returns (bool) {
        require(lastDitCoordinator != address(0));
        ditCoordinator last = ditCoordinator(lastDitCoordinator);

        uint256 _currentProposalID = last.getCurrentProposalID(_repository);
        uint256 _votingMajority = last.getVotingMajority(_repository);
        string[3] memory _knowledgeLabels;
        for (uint8 i = 0; i < 3; i++) {
            _knowledgeLabels[i] = last.getKnowledgeLabels(_repository, i);
        }

        repositories[_repository] = ditRepository({
            knowledgeLabels: _knowledgeLabels,
            currentProposalID: _currentProposalID,
            votingMajority: _votingMajority
        });

        KNWVote.addNewRepository(_repository, _votingMajority);

        return true;
    }

    /**
     * @dev Gets a ditCraft-based repositories ditContract address
     * @param _repository The descriptor of the repository (e.g. keccak256("github.com/example_repo"))
     * @return A boolean that indicates if the operation was successful
     */
    function repositoryIsInitialized(bytes32 _repository) external view returns (bool) {
        return repositories[_repository].votingMajority > 0;
    }

    // Proposing a new commit for the repository
    function proposeCommit(bytes32 _repository, uint256 _knowledgeLabelIndex, uint256 _voteCommitDuration, uint256 _voteOpenDuration) external payable onlyPassedKYC(msg.sender) {
        require(msg.value > 0, "Value of the transaction can not be zero");
        require(bytes(repositories[_repository].knowledgeLabels[_knowledgeLabelIndex]).length > 0, "Knowledge-Label index is not correct");
        require(_voteCommitDuration >= MIN_VOTE_DURATION && _voteCommitDuration <= MAX_VOTE_DURATION, "Vote commit duration invalid");
        require(_voteOpenDuration >= MIN_OPEN_DURATION && _voteOpenDuration <= MAX_OPEN_DURATION, "Vote open duration invalid");
        require(nextDitCoordinator == address(0), "There is a newer contract deployed");
        repositories[_repository].currentProposalID = repositories[_repository].currentProposalID.add(1);

        // Creating a new proposal
        proposalsOfRepository[_repository][repositories[_repository].currentProposalID] = commitProposal({
            KNWVoteID: KNWVote.startVote(_repository, msg.sender, repositories[_repository].knowledgeLabels[_knowledgeLabelIndex], _voteCommitDuration, _voteOpenDuration, msg.value),
            knowledgeLabel: repositories[_repository].knowledgeLabels[_knowledgeLabelIndex],
            proposer: msg.sender,
            isFinalized: false,
            proposalAccepted: false,
            individualStake: msg.value,
            totalStake: msg.value
        });

        emit ProposeCommit(_repository, repositories[_repository].currentProposalID, msg.sender, repositories[_repository].knowledgeLabels[_knowledgeLabelIndex]);
    }

    // Casting a vote for a proposed commit
    function voteOnProposal(bytes32 _repository, uint256 _proposalID, bytes32 _voteHash) external payable onlyPassedKYC(msg.sender) {
        require(msg.value == proposalsOfRepository[_repository][_proposalID].individualStake, "Value of the transaction doesn't match the required stake");
        require(msg.sender != proposalsOfRepository[_repository][_proposalID].proposer, "The proposer is not allowed to vote in a proposal");
        
        // Increasing the total stake of this proposal (necessary for security purposes during the payout)
        proposalsOfRepository[_repository][_proposalID].totalStake = proposalsOfRepository[_repository][_proposalID].totalStake.add(msg.value);

        // The vote contract returns the number of votes that the voter has in this vote (including the KNW influence)
        uint256 numberOfVotes = KNWVote.commitVote(proposalsOfRepository[_repository][_proposalID].KNWVoteID, msg.sender, _voteHash);
        require(numberOfVotes > 0, "Voting contract returned an invalid amount of votes");

        proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].numberOfVotes = numberOfVotes;

        emit CommitVote(_repository, _proposalID, msg.sender, proposalsOfRepository[_repository][_proposalID].knowledgeLabel, msg.value, numberOfVotes);
    }

    // Revealing a vote for a proposed commit
    function openVoteOnProposal(bytes32 _repository, uint256 _proposalID, uint256 _voteOption, uint256 _voteSalt) external onlyPassedKYC(msg.sender) {
        KNWVote.openVote(proposalsOfRepository[_repository][_proposalID].KNWVoteID, msg.sender, _voteOption, _voteSalt);
        
        // Saving the option of the voter
        proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].choice = _voteOption;
        emit OpenVote(_repository, _proposalID, msg.sender, proposalsOfRepository[_repository][_proposalID].knowledgeLabel, (_voteOption == 1), proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].numberOfVotes);
    }

    // Resolving a vote
    // Note: the first caller will automatically resolve the proposal
    function finalizeVote(bytes32 _repository, uint256 _proposalID) external onlyPassedKYC(msg.sender) {
        require(!proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].hasFinalized, "Each participant can only finalize once");
        require(proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].numberOfVotes > 0 || proposalsOfRepository[_repository][_proposalID].proposer == msg.sender, "Only participants of the vote are able to resolve the vote");

        // If the proposal hasn't been resolved this will be done by the first caller
        if(!proposalsOfRepository[_repository][_proposalID].isFinalized) {
            proposalsOfRepository[_repository][_proposalID].proposalAccepted = KNWVote.endVote(proposalsOfRepository[_repository][_proposalID].KNWVoteID);
            proposalsOfRepository[_repository][_proposalID].isFinalized = true;

            emit FinalizeVote(_repository, _proposalID, proposalsOfRepository[_repository][_proposalID].knowledgeLabel, proposalsOfRepository[_repository][_proposalID].proposalAccepted);
        }
        
        // The vote contract returns the amount of ETH that the participant will receive
        uint256 value = KNWVote.finalizeVote(proposalsOfRepository[_repository][_proposalID].KNWVoteID, proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].choice, msg.sender);
        
        // If the value is greater than zero, it will be transferred to the caller
        if(value > 0) {
            msg.sender.transfer(value);
        }
        
        proposalsOfRepository[_repository][_proposalID].totalStake = proposalsOfRepository[_repository][_proposalID].totalStake.sub(value);
        proposalsOfRepository[_repository][_proposalID].participantDetails[msg.sender].hasFinalized = true;
    }

    function getIndividualStake(bytes32 _repository, uint256 _proposalID) external view returns (uint256 individualStake) {
        return proposalsOfRepository[_repository][_proposalID].individualStake;
    }

    // Returns whether a proposal has passed or not
    function proposalHasPassed(bytes32 _repository, uint256 _proposalID) external view returns (bool hasPassed) {
        require(proposalsOfRepository[_repository][_proposalID].isFinalized, "Proposal hasn't been resolved");
        return proposalsOfRepository[_repository][_proposalID].proposalAccepted;
    }

    function getKnowledgeLabels(bytes32 _repository, uint256 _knowledgeLabelID) external view returns (string knowledgeLabel) {
        return repositories[_repository].knowledgeLabels[_knowledgeLabelID];
    }

    function getVotingMajority(bytes32 _repository) external view returns (uint256) {
        return repositories[_repository].votingMajority;
    }

    function getCurrentProposalID(bytes32 _repository) external view returns (uint256) {
        return repositories[_repository].currentProposalID;
    }

    function getKNWVoteIDFromProposalID(bytes32 _repository, uint256 _proposalID) external view returns (uint256) {
        return proposalsOfRepository[_repository][_proposalID].KNWVoteID;
    }

    modifier onlyPassedKYC(address _address) {
        require(passedKYC[_address]);
        _;
    }

    modifier onlyKYCValidator(address _address) {
        require(isKYCValidator[_address]);
        _;
    }
}