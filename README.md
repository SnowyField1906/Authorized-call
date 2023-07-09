---
status: draft 
flip: 118
authors: Huu Thuan Nguyen (nguyenhuuthuan25112003@gmail.com) 
sponsor: None
updated: 2023-06-30
---

# FLIP 118: Authorized Call

## Objective

> What are we doing and why? What problem will this solve? What are the goals and non-goals? This is your executive summary; keep it short, elaborate below.

The objective of this FLIP is to introduce the "Authorized Call" feature, which allows functions to be marked as private unless they are called with a specific prefix.

This feature aims to enhance access control in Contracts, providing developers with more flexibility and fine-grained control over function visibility based on caller Contracts.

## Motivation

> Why is this a valuable problem to solve? What background information is needed to show how this design addresses the problem?
> Which users are affected by the problem? Why is it a problem? What data supports this? What related work exists?

Flow introduced Cadence - a Resource-Oriented Programming Language which works towards the Capability system, it replaced `msg.sender` and proved to be effective for small projects. \
However, as projects grow in size and complexity, the efficiency of the Capability system decreases compared to the use of `msg.sender`.

Besides, The existing access control mechanisms is relatively simple, they have limitations when it comes to defining private functions that can only be accessed under specific circumstances. This can make it challenging for developers to enforce strict access control rules in complex projects.

To illustrate the issue, let's consider a specific example. Suppose we have a `Vault` Contract with a function called `Vault.swap()`, which should only be called by the `Core` Contract or `Router` Contracts.

```cadence
access(all) contract Vault {
    access(all) resource Admin {
        access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
            return <- Vault._swap(from: <- from)
        }
    }
    
    access(self) fun _swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        // some implementation
    }

    access(account) fun createAdmin(): @Admin {
        return <- create Vault.Admin()
    }
}
```

Currently, we can achieve this with Flow using different approaches:

Approach 1: Saving the `Admin` Resource to the `Router` deployer account.

```cadence
access(all) contract Router {
    access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        return self.account.borrow<&Vault.Admin>(from: /storage/VaultAdmin)!.swap(from: <- from)
    }
}
```

Approach 2: Saving the `Admin` Capability to the `Router` Contract.

```cadence
access(all) contract Router {
    let vaultAdmin: Capability<&Vault.Admin>

    access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        return self.vaultAdmin.swap(from: <- from)
    }

    init(vaultAdmin: Capability<&Vault.Admin>) {
        self.vaultAdmin = vaultAdmin
    }
}
```

However, both approaches have drawbacks:

- The `Admin` Resource definition increases the code size and makes maintenance and updates more challenging.
- Adding a new `Router` Contract requires operating with the `Vault` deployer account, reducing decentralization and introducing unnecessary steps.
- As projects become larger and require more complex access control rules, the need for additional Resources meeting some specific requirements increases, which leads to a more significant increase in code size.

## User Benefit

> How will users (or other contributors) benefit from this work? What would be the headline in the release notes or blog post?

This proposal is aimed at making Contracts more decentralized, independent of the deployer account. This will be easier to manage and friendly to high complexity projects.

## Design Proposal

> This is the meat of the document where you explain your proposal. If you have multiple alternatives, be sure to use sub-sections for better separation of the idea, and list pros/cons to each approach. If there are alternatives that you have eliminated, you should also list those here, and explain why you believe your chosen approach is superior.

> Make sure you’ve thought through and addressed the following sections. If a  section is not relevant to your specific proposal, please explain why, e.g.  your FLIP addresses a convention or process, not an API.

The proposed design introduces the following enhancements:

### Upgradations to the `auth` and `access` keywords

This `auth` keyword existed in Cadence as a modifier for References to make it freely upcasted and downcasted. \
But in this proposal, it is also combined with `access` to mark a function as private unless it is called with an `auth` prefix.

Inside the function, the `auth` prefix can be used to access the caller Contract.

```cadence
// FooContract.cdc
access(auth) fun foo() {
    log(auth.account.address) // The caller Contract address
}
```

In order to make a call to `foo()`, it must have the `auth` prefix which means it is accepted to be identified.

```cadence
// BarContract.cdc
// Deployed at 0x01
import FooContract from "FooContract"

FooContract.foo() // Invalid
auth FooContract.foo() // Valid, log: 0x01
```

Once it is possible to access the caller Contract and utilize its functionalities, developers can build powerful features and implement complex logic to ensure Contract security besides enhance the flexibility and extensibility of Contracts.

### Improvements to the `import` keyword

With this prefix, we can import the whole Contract as authorized, which all calls to the Contract will be marked as `auth` without the prefix.

```cadence
// BarContract.cdc
// Deployed at 0x01
import FooContract as auth from "FooContract"

FooContract.foo() // Valid, log: 0x01
```


### Authorized Contracts

A contract can be marked as authorized, which needs to be imported with the `auth` prefix, otherwise, it will be completely inaccessible.

```cadence
// FooContract.cdc
access(auth) contract FooContract {
    access(self) fun _foo() { }
    access(all) fun foo() { }
}

// BarContract.cdc
import FooContract from "FooContract" // Invalid
import FooContract as auth from "FooContract" // Valid

FooContract._foo() // Invalid
FooContract.foo() // Valid
```

### Interface integration

```cadence
// FooInterface.cdc
access(all) contract interface FooInterface {
    access(all) let queue: [Addess]
    access(auth) fun foo() {
        pre {
            self.queue[auth.account.address] == nil: "Already joined"
        }
    }
}

// FooContract.cdc
access(auth) contract FooContract: FooInterface {
    access(all) let queue: [Addess] = [0x01]
    access(auth) fun foo();
}

// BarContract.cdc
// Deployed at 0x01
FooContract.foo() // pre-condition failed: Already joined

// AnotherBarContract.cdc
// Deployed at 0x02
FooContract.foo() // Valid
```

### Sample use cases

#### Example 1

In this example, we demonstrate how to restrict access to functions using `auth` keywords.

Supposes we have a `Vault` Contract with a `Vault._swap()` function which should be restricted to be callable only by either `Plugin` or `Router` Contracts.

```cadence
// Vault.cdc
access(all) contract Vault {
    access(all) let approvedContracts: [Address] = [0x01]
    access(auth) fun _swap(from: @FungibleToken.Vault, expectedAmount: UFix64): @FungibleToken.Vault {
        assert(self.approvedContracts.contains(auth.account.address), message: "Not authorized")
        
        let to: @FungibleToken = self._swap(
            from: <- from,
            expectedAmount: expectedAmount
        )

        return to
    }
    access(all) fun exactInput(amountIn: UFix64): UFix64;
}
```

Now, let's explore how `Plugin` Contract can call `Vault._swap()`.

```cadence
// Plugin.cdc
// Deployed at 0x01
access(all) contract Plugin: IPlugin {
    access(all) fun invalidSwap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        let to: @FungibleToken = Vault._swap(
            from: <- from,
            expectedAmount: 0.01
        ) // -> assertion failed: Not authorized
    }
    access(all) fun validSwap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        let to: @FungibleToken = auth Vault._swap(
            from: <- from,
            expectedAmount: someAmount
        ) // Valid call

        return to
    }
}
```

#### Example 3

```cadence
// Nodes.cdc
access(all) contract Nodes {
    access(all) let validExecutions: [Address] = [0x01]
    access(all) let MINIMUM_STAKED: UFix64 = 1250000.0

    access(Router | GOV) fun addExecution(execution: Address)
    access(Collection | Consensus | Execution | Verification) fun withdrawn();

    access(Execution) fun executed() {
        let exeAddr: Address = Execution.account.address
        assert(Nodes.validExecutions.exists(exeAddr), message: "Execution is not valid")

        let balance: UFix64 = getAccount(Execution.account.address).balance
        assert(balance >= Nodes.minimumStaked: "Execution is not staked enough")
    }
}

// InvalidExecution.cdc
// Deployed at 0x02
access(all) contract InvalidExecution: IExecution {
    access(all) fun execute() {
        Nodes.executed() // -> assertion failed: Execution is not valid
    }
}
// PoorExecution.cdc
// Deployed at 0x01 and had less than 1.250.000 Flow
access(all) contract PoorExecution: IExecution {
    access(all) fun execute() {
        Nodes.executed() // -> assertion failed: Execution is not staked enough
    }
}
// ValidExecution.cdc
// Deployed at 0x01 and had over 1.250.000 Flow
access(all) contract ValidExecution: IExecution {
    access(all) fun execute() {
        Nodes.executed() // Valid
    }
}
```

#### Example 4

```cadence
// Bank.cdc
define Balance from SpecialBalance { }
define Receiver from SpecialReceiver { }
define Provider from SpecialProvider { }

group (Balance & Receiver & Provider) as Vault

access(all) contract Bank {
    access(Balance) fun getInterest(): UFix64;

    access(Provider) fun withdrawAll();

    access(Vault) fun subscribed()
}

// BankVault.cdc
access(all) resource interface SpecialBalance {
    access(all) fun getAvailableBalance(): UFix64;

    access(all) fun getAllPossibleBalance(): UFix64 {
        return self.getAvailableBalance() + Bank.getInterest() // Valid from SpecialBalance
    }
}
access(all) resource interface SpecialProvider {
    access(all) fun withdraw(amount: UFix64): @FungibleToken.Vault;

    access(all) fun withdrawAll(): @FungibleToken.Vault {
        Bank.withdrawAll() // Valid from Provider
        // Some implementation
    }
}
access(all) resource SpecialVault: SpecialBalance, SpecialReceiver, SpecialProvider {
    // Some implementation

    access(all) fun subscribe() {
        Bank.subscribed() // Valid from (SpecialBalance & SpecialReceiver & SpecialProvider)
    }
}
```

### Drawbacks

>Why should this *not* be done? What negative impact does it have?

Since the [`entitlement` FLIP](https://github.com/onflow/flips/blob/main/cadence/20221214-auth-remodel.md) was approved, this might cause some confusion and conficts in syntax and semantics.

### Alternatives Considered

> Make sure to discuss the relative merits of alternatives to your proposal.


### Performance Implications

> Do you expect any (speed / memory)? How will you confirm?

> There should be microbenchmarks. Are there?

> There should be end-to-end tests and benchmarks. If there are not (since this is still a design), how will you track that these will be created?

### Dependencies

> Dependencies: does this proposal add any new dependencies to Flow?

> Dependent projects: are there other areas of Flow or things that use Flow  (Access API, Wallets, SDKs, etc.) that this affects? How have you identified these dependencies and are you sure they are complete?  If there are dependencies, how are you managing those changes?

### Engineering Impact

> Do you expect changes to binary size / build time / test times?

> Who will maintain this code? Is this code in its own buildable unit? Can this code be tested in its own?  Is visibility suitably restricted to only a small API surface for others to use?

### Best Practices

> Does this proposal change best practices for some aspect of using/developing Flow? How will these changes be communicated/enforced?

### Tutorials and Examples

> If design changes existing API or creates new ones, the design owner should create end-to-end examples (ideally, a tutorial) which reflects how new feature will be used. Some things to consider related to the tutorial:
> - It should show the usage of the new feature in an end to end example (i.e. from the browser to the execution node). Many new features have unexpected effects in parts far away from the place of change that can be found by running through an end-to-end example.
> - This should be written as if it is documentation of the new feature, i.e., consumable by a user, not a Flow contributor.
> - The code does not need to work (since the feature is not implemented yet) but the expectation is that the code does work before the feature can be merged.

### Compatibility

> Does the design conform to the backwards & forwards compatibility [requirements](../docs/compatibility.md)?

> How will this proposal interact with other parts of the Flow Ecosystem?
> - How will it work with FCL?
> - How will it work with the Emulator?
> - How will it work with existing Flow SDKs?

### User Impact

> What are the user-facing changes? How will this feature be rolled out?

## Related Issues

> What related issues do you consider out of scope for this proposal, but could be addressed independently in the future?

## Prior Art

> Does the proposed idea/feature exist in other systems and what experience has their community had?

> This section is intended to encourage you as an author to think about the lessons learned from other projects and provide readers of the proposal with a fuller picture.

> It's fine if there is no prior art; your ideas are interesting regardless of whether or not they are based on existing work.

## Questions and Discussion Topics

> Seed this with open questions you require feedback on from the FLIP process.

> What parts of the design still need to be defined?
