---
status: draft
flip: 198
authors: Huu Thuan Nguyen (nguyenhuuthuan25112003@gmail.com)
sponsor: None
updated: 2023-09-18
---

# FLIP 198: Authorized Call

## Objective

The objective of this FLIP is to introduce the "Authorized Call" feature, which allows functions to be marked as private unless they are called with a specific prefix.

This feature aims to enhance access control in Contracts, providing developers with more flexibility and fine-grained control over function visibility based on caller Contracts.

## Motivation

Flow introduced Cadence - a Resource-Oriented Programming Language which works towards the Capability system, it replaced `msg.sender` and proved to be effective for small projects. \
However, as projects grow in size and complexity, the efficiency of the Capability system decreases compared to the use of `msg.sender`.

Besides, The existing access control mechanisms is relatively simple, they have limitations when it comes to defining private functions that can only be accessed under specific circumstances. This can make it challenging for developers to enforce strict access control rules in complex projects.

To illustrate the issue, let's consider a specific example. Suppose we have a `Vault` Contract with a function called `Vault.swap()`, which should only be called by the `Plugin` Contracts.

```cadence
access(all) contract Vault {
    access(all) resource Admin {
        access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
            return <- Vault._swap(from: <- from);
        }
    }

    access(self) fun _swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        // some implementation
    }

    access(account) fun createAdmin(): @Admin {
        return <- create Vault.Admin();
    }
}
```

Currently, we can achieve this with Flow using different approaches:

Approach 1: Saving the `Admin` Resource to the `Plugin` deployer account.

```cadence
access(all) contract Plugin {
    access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        return self.account.borrow<&Vault.Admin>(from: /storage/VaultAdmin)!.swap(from: <- from);
    }
}
```

Approach 2: Saving the `Admin` Capability to the `Plugin` Contract.

```cadence
access(all) contract Plugin {
    let vaultAdmin: Capability<&Vault.Admin>;

    access(all) fun swap(from: @FungibleToken.Vault): @FungibleToken.Vault {
        return self.vaultAdmin.swap(from: <- from);
    }

    init(vaultAdmin: Capability<&Vault.Admin>) {
        self.vaultAdmin = vaultAdmin;
    }
}
```

However, both approaches have drawbacks:

- The `Admin` Resource definition increases the code size and makes maintenance and updates more challenging.
- Adding a new `Plugin` Contract requires operating with the `Vault` deployer account, reducing decentralization and introducing unnecessary steps.
- As projects become larger and require more complex access control rules, the need for additional Resources meeting some specific requirements increases, which leads to a more significant increase in code size.

## User Benefit

This proposal is aimed at making Contracts more decentralized, independent of the deployer account. This will be easier to manage and friendly to high complexity projects.

## Design Proposal

The proposed design introduces the following enhancements:

### Upgradations to the `auth` and `access` keywords

This `auth` keyword existed in Cadence as a modifier for References to make it freely upcasted and downcasted. \
But in this proposal, it is also combined with `access` to mark a function as private unless it is called with an `auth` prefix.

Inside the function, the `auth` prefix can be used to access the caller Contract.

```cadence
// FooContract.cdc
access(auth) fun foo() {
    log(auth.address); // The caller Contract address
}
```

In order to make a call to `foo()`, it must have the `auth` prefix which means it is accepted to be identified.

```cadence
// BarContract.cdc
// Deployed at 0x01
import FooContract from "FooContract";

FooContract.foo(); // -> Invalid, `auth` is missing
auth FooContract.foo(); // Valid, log: 0x01
```

Once it is possible to access the caller Contract and utilize its functionalities, developers can build powerful features and implement complex logic to ensure Contract security besides enhance the flexibility and extensibility of Contracts.

### Improvements to the `import` keyword

With this prefix, we can import the whole Contract as authorized, which all calls to the Contract will be marked as `auth` without the prefix.

```cadence
// BarContract.cdc
// Deployed at 0x01
import FooContract as auth from "FooContract";

FooContract.foo(); // Valid, log: 0x01
```

### Authorized Contracts

A contract can be marked as authorized, which needs to be imported with the `auth` prefix, otherwise, it will be completely inaccessible.

```cadence
// FooContract.cdc
access(auth) contract FooContract {
    access(self) fun _foo();
    access(all) fun foo();
}

// BarContract.cdc
import FooContract from "FooContract"; // Invalid, `auth` is missing

import FooContract as auth from "FooContract"; // Valid
FooContract.foo(); // Valid
```

### Interface integration

This proposal also supports the `auth` keyword in Interfaces, which can be used to restrict access to the functions where its contract implements those Interfaces.

```cadence
// FooInterface.cdc
access(all) contract interface FooInterface {
    access(all) let queue: [Addess];

    access(auth) fun foo() {
        pre {
            self.queue[auth.address] == nil: "Already joined"
        }
    }
}

// FooContract.cdc
access(auth) contract FooContract: FooInterface {
    access(all) let queue: [Addess] = [0x01];
    access(auth) fun foo();
}

// BarContract.cdc
// Deployed at 0x01
auth FooContract.foo(); // pre-condition failed: Already joined

// AnotherBarContract.cdc
// Deployed at 0x02
auth FooContract.foo(); // Valid
```

### Transaction integration

Not only supports the function to determine the caller Contract, but this proposal also can determine the caller Account (the Authorizer) in Transactions.

Multiple authorizers may be specified in the Transaction.

Due to basing on the Authorizer account, it can only be done in the `prepare` phase. And the `auth` keyword can be changed by the argument label.

```cadence
// the Authorizer address is 0x01
transaction() {
    prepare(auth: AuthAccount) {
        auth FooContract.foo(); // Valid, log: 0x01
    }
}

// the Authorizer addresses are 0x01 and 0x02
transaction() {
    prepare(auth1: AuthAccount, auth2: AuthAccount) {
        auth1 FooContract.foo(); // Valid, log: 0x01
        auth2 FooContract.foo(); // Valid, log: 0x02
        auth FooContract.foo(); // Invalid, `auth` is ambiguous
    }
}
```

### Alternatives Considered

The keyword `auth` can be considered to be replaced with other keywords.

### Dependencies

Actually, these are just functions having a hidden argument called `auth`, it is hidden to ensure that the caller cannot pass fake values to the function. \

When calling an `auth` function, the Contract address is passed internally into it.

```cadence
access(auth) fun foo(/* auth: PublicAccount */); // auth is a hidden argument
```

### Tutorials and Examples

In the below examples, we demonstrate how to restrict access to functions using `auth` keywords.

#### Example 1

Supposes there is a dangerous function should not be called by itself or the deployer account.

```cadence
access(auth) fun dangerousFoo() {
    assert(auth.address != self.account.address, message: "Forbidden");
}
```

#### Example 2

Supposes we have a `Vault` Contract with a `Vault._swap()` function which should be restricted to be callable only by specific `Plugin` Contracts.

```cadence
// Vault.cdc
access(all) contract Vault {
    access(all) let approvedPlugins: [Address] = [0x01];

    access(auth) fun _swap(from: @FungibleToken.Vault, expectedAmount: UFix64) {
        pre {
            self.approvedPlugins.contains(auth.address): "Not authorized"
        }

        return <- expected;
    }
}
```

#### Example 3

```cadence
// Nodes.cdc
access(all) contract Nodes {
    access(all) let validExecutions: [Address] = [0x01];
    access(all) let MINIMUM_STAKED: UFix64 = 1250000.0;

    access(auth) fun executed() {
        pre {
            self.validExecutions.contains(auth.address): "Not authorized"
            auth.balance >= self.MINIMUM_STAKED: "Not staked enough"
        }
    }
}

// InvalidExecution.cdc
// Deployed at 0x02
access(all) contract InvalidExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed(); // -> assertion failed: Not authorized
    }
}
// PoorExecution.cdc
// Deployed at 0x01 and had less than 1.250.000 Flow
access(all) contract PoorExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed(); // -> assertion failed: Not staked enough
    }
}
// ValidExecution.cdc
// Deployed at 0x01 and had over 1.250.000 Flow
access(all) contract ValidExecution: IExecution {
    access(all) fun execute() {
        auth Nodes.executed(); // Valid
    }
}
```

## Prior Art

This works similarly to the `msg.sender` in Solidity (not `tx.origin`).
