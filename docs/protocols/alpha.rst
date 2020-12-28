.. _alpha:

Protocol Alpha
==============

This page contains all the relevant information for protocol Alpha, a
development version of the Tezos protocol.

The code can be found in the ``src/proto_alpha`` directory of the
``master`` branch of Tezos.

This page documents the changes brought by Protocol Alpha with respect
to Edo.


- Proto/Michelson: disallow empty entrypoints in string addresses

  Fixes: https://gitlab.com/tezos/tezos/-/issue/643

- Rename the voting periods as follows:
  1. Proposal       --> Proposal
  2. Testing_vote   --> Exploration
  3. Testing        --> Cooldown
  4. Promotion_vote --> Promotion
  5. Adoption       --> Adoption

- The protocol does not spawn a testchain during the third voting period, now called `Cooldown` period