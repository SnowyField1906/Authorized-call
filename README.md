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

> Make sure you’ve thought through and addressed the following sections. If a section is not relevant to your specific proposal, please explain why, e.g. your FLIP addresses a convention or process, not an API.

The proposed design introduces the following enhancements:

### Upgradations to the `auth` and `access` keywords

This `auth` keyword existed in Cadence as a modifier for References to make it freely upcasted and downcasted. \
But in this proposal, it is also combined with `access` to mark a function as private unless it is called with an `auth` prefix.

Inside the function, the `auth` prefix can be used to access the caller Contract.

```cadence:FooContract.cdc
// FooContract.cdc
access(auth) fun foo() {
    log(auth.address) // The caller Contract address
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
            self.queue[auth.address] == nil: "Already joined"
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
auth FooContract.foo() // pre-condition failed: Already joined

// AnotherBarContract.cdc
// Deployed at 0x02
auth FooContract.foo() // Valid
```

### Drawbacks

> Why should this _not_ be done? What negative impact does it have?

Since the [`entitlement` FLIP](https://github.com/onflow/flips/blob/main/cadence/20221214-auth-remodel.md) was approved, this might cause some confusion and conficts in syntax and semantics.

### Alternatives Considered

> Make sure to discuss the relative merits of alternatives to your proposal.

The keyword `auth` can be considered to be replaced with other keywords.

### Dependencies

> Dependencies: does this proposal add any new dependencies to Flow?

> Dependent projects: are there other areas of Flow or things that use Flow (Access API, Wallets, SDKs, etc.) that this affects? How have you identified these dependencies and are you sure they are complete? If there are dependencies, how are you managing those changes?

Actually, these are just functions having a hidden parameter called `auth`, it is hidden to ensure that the caller cannot pass fake values to the function. \

When calling an `auth` function, the Contract address is passed internally into it.

```cadence
access(auth) fun foo(/* auth: PublicAccount */); // auth is a hidden parameter
```

### Tutorials and Examples

In the below examples, we demonstrate how to restrict access to functions using `auth` keywords.

#### Example 1

Supposes there is a dangerous should not call by the deployer account (or only the deployer account can call it).

We can implement it as follows:

```cadence
access(auth) fun dangerousFoo() {
    assert(auth.address == self.account.address, message: "Not authorized")
}
```

#### Example 2

Supposes we have a `Vault` Contract with a `Vault._swap()` function which should be restricted to be callable only by either `Plugin` or `Router` Contracts.

```cadence
// Vault.cdc
access(all) contract Vault {
    access(all) let approvedContracts: [Address] = [0x01]
    access(auth) fun _swap(from: @FungibleToken.Vault, expectedAmount: UFix64): @FungibleToken.Vault {
        assert(self.approvedContracts.contains(auth.address), message: "Not authorized")

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

    access(auth) fun executed() {
        pre {
            self.validExecutions.exists(auth.address): "Execution is not valid"
            auth.balance >= self.MINIMUM_STAKED: "Execution is not staked enough"
        }
    }
}

// InvalidExecution.cdc
// Deployed at 0x02
access(all) contract InvalidExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed() // -> assertion failed: Execution is not valid
    }
}
// PoorExecution.cdc
// Deployed at 0x01 and had less than 1.250.000 Flow
access(all) contract PoorExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed() // -> assertion failed: Execution is not staked enough
    }
}
// ValidExecution.cdc
// Deployed at 0x01 and had over 1.250.000 Flow
access(all) contract ValidExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed() // Valid
    }
}
```

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

```

```
