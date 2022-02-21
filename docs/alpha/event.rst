Event logging
=============

Event logging in contract is a way for contracts to deliver event-like information to external application.
It is an important pattern in contract writing to allow external applications to respond to communication
from Tezos contracts to effect changes in application states outside Tezos.
There is blossoming use of event logs in basic indexing services and cross-chain bridges or applications.
In this document, we will explain how event logs are supported in Tezos contract on the Michelson level.

Event
-----
A contract event entry in Tezos consists of the following data.

- An event ``tag`` of type ``string``
- An event ``data`` of type ``event``
  which is declared by the emitting contract in a similar way to declaration of ``storage`` and ``parameter``
- An event ``emitter`` identifier indicating the contract emitting this event
- An event ``origin`` identifier indicating the origin of the chain of operations that eventually leads to
  the construction of this event entry, which is usually the payer of the first transaction in the chain

Each successful contract execution attaches a list of contract events arranged in the chronological order
to the transaction receipt made ready for consumption by services observing the chain.

Runtime semantics
-----------------
To support event logging, an instruction ``EMIT`` is introduced into the Michelson language.
In this case, event emitting contracts are obliged to declare an event type at its top-level Michelson code,
along with the compulsory ``storage`` and ``parameter``.
Other contracts not emitting any events may omit this declaration, and a ``never`` type will be assigned to
the ``event`` type in lieu.

Events shall be emitted at places other than lambdas and views for a few reasons.
  - Lambdas could be packed, transmitted, and executed in different contracts.
    Emitting events in lambda bodies leads to ambiguous identification of the event source and, thus,
    should be avoided for security reasons.
  - Lambdas could be executed repeatedly combined with ``List.map``.
    Emitting events in this scenario could lead to excessive logging that may be out of the control of
    the contract author.
  - Views are short computation on immutable contract data.
    Emitting events in this case hardly produces useful information while introducing unneccesary latency to
    the computation.

Emitting events is also allowed in bodies of new contracts to be created via ``Icreate_contract``.