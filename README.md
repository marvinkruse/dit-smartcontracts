# Smart Contracts

As the corner-stone of ditcraft, the smart contracts serve the most important purpose of the implementation. Nameley these are the **KNWToken, KNWVoting, ditCoordinator and the ditContract**s.

## Deployed Contracts
The contracts are currently deployed on the Rinkeby testnet for development and testning purposes.
- ditCoordinator: [0x808d9B0E0b36DCd34b64113F4c2AabadDc15743f](https://rinkeby.etherscan.io/address/0x808d9B0E0b36DCd34b64113F4c2AabadDc15743f)
- KNWToken: [0xB999a62981f84674Eb72806Ba752ff9526Abab22](https://rinkeby.etherscan.io/address/0xB999a62981f84674Eb72806Ba752ff9526Abab22)
- KNWVoting: [0x1BD208B3A0ADAbf8d4a0E08E2B02fF63057a66E9](https://rinkeby.etherscan.io/address/0x1BD208B3A0ADAbf8d4a0E08E2B02fF63057a66E9)

Note: *You will need some ETH to interact with the contracts.*


## Contract Description
### KNWToken
The KNWToken is a modified version of the ERC20 token, comparable to the [ERC888 proposal](https://github.com/ethereum/EIPs/issues/888). It has the following external interfaces:

 - `totalsupply()` 
	- returns the total count of KNW tokens
 - `totalLabelSupply(label)` 
	 - returns the total count of KNW tokens for a certain label
 - `balanceOfLabel(address, label)` 
	 - returns the count of KNW tokens for a certain label of a certain address
 - `freeBalanceOfLabel(address, label)`
	 - returns the free (non-locked) count of KNW tokens for a certain label of a certain address
 - `labelsOfAddress(address)` 
	 - returns the labels that a certain address has a token count for
 - `lockTokens(address, label)`
	 - locks and returns the remaining free amount of KNW tokens for a certain label of a certain address to be used in a vote (*this function can only be called by the KNWVoting Contract*)
 - `unlockTokens(address, label, amount)`
	 - unlocks specified amount of KNW tokens for a certain label of a certain address that were used in a vote (*this function can only be called by the KNWVoting Contract*)
 - `mint(address, label, winningPercentage, mintingMethod)` 
	 - will mint new KNWTokens for the specified address according to the specified method and the winningPercentage of the vote (*this function can only be called by the KNWVoting Contract*)
 - `burn(address, label, amount)` 
	 - will burn KNWTokens of the specified address according to the specified method and the winningPercentage of the vote (*this function can only be called by the KNWVoting Contract*)

Note that this Contract doesn't have transfer functions, as KNW tokens are not transferable. 

### KNWVoting
KNWVoting is a highly modified version of the [PLCR Voting scheme by Mike Goldin](https://github.com/ConsenSys/PLCRVoting). It has the following external interfaces:

 - `startPoll(address, knowledgeLabel, commitDuration, revealDuration, stake)`
	 -  starts a new poll according to the provided settings
 - `commitVote(pollID, address, hash)`
	 -  commits a vote hash\* (this alss triggers the locking of KNW tokens)
 - `revealVote(pollID, address, choice, salt)`
	 - reveals the committed vote to the public
 - `resolveVote(pollID)`
	 - resolves the vote, calculated the outcome and returns the reward to the calling contract (also triggers the minting/burning of KNW tokens)

Note that all of the functions that start or interact with votes can only be called via ditContracts.
\* = The vote is committed with hash = (choice|salt) where choice = {0, 1} and salt = {0, 2^256-1}

### ditCoordinator
The ditCoordinator contract is the central piece of this architecture. It has the following external interfaces:

 - `getRepository(repository)`
	 -  returns information about a repository (including the address of its ditContract)
 - `initRepository(repository, knowledge_labels, voteSettings)`
	 -  creates a ditContract for a new repository with the specified settings

### ditContract
The ditContracts are the controlling instance for every repository. This is the point of interaction for the users with the repository/votes. It has the following external interfaces:

 - `proposeCommit(label)`
	 -  initiates a new proposal and thus starts a new vote
 - `voteOnProposal(proposalID, voteHash)` (also triggers the locking of KNW tokens)
	 -  votes on a proposal with the hashed vote
 - `revealVoteOnProposal(proposalID, choice, salt)`
	 - reveals the vote on a proposal to the public
 - `resolveVote(proposalID)`
	 - first caller: automatically resolves the proposal and signals the developer that a merge to the main branch is now possible 
	 - everyone: claims the reward of the participant for this proposals' vote (also triggers the minting/burning of KNW tokens)
	 