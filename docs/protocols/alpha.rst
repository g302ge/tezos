Protocol Alpha
==============

This page contains all the relevant information for protocol Alpha
(see :ref:`naming_convention`).

The code can be found in the :src:`src/proto_alpha` directory of the
``master`` branch of Tezos.

This page documents the changes brought by protocol Alpha with respect
to Protocol I.

.. contents::

New Environment Version (V5)
----------------------------

This protocol requires a different protocol environment than Ithaca.
It requires protocol environment V5, compared to V4 for Ithaca.
(MR :gl:`!4071`)

- Remove compatibility layers. (MR :gl:`!4215`)

- Lwtreslib updates from stdlib 4.13. (MR :gl:`!4279`)

- Upstream compact encoding from lib_protocol to lib_base. (MR :gl:`!4339`)

- Add Merkle proofs to the protocol. (MR :gl:`!4086`)

- Update Bls_signature to bls12-381.2.0.1. (MR :gl:`!4383`)

- Add pk/signature_size_in_bytes in Bls_signature. (MR :gl:`!4492`)

- Add size_in_memory for BLS types and reset test configurations of for the
  typed IR size to previous values. (MR :gl:`!4464`)

- Context Merkle proof encoding. (MR :gl:`!4307`)

- Update to data encoding 0.5. (MR :gl:`!4582`)

- Provide let* binding operators. (MR :gl:`!4365`)

- Expose `Blake2b.Make_merkle_tree`. (MR :gl:`!4618`)

- Add Merkle proof encoding specialized for binary trees and encodings using
  Compact_encoding. (MR :gl:`!4509`)

- Sync interfaces with upstreams. (MR :gl:`!4617`)

- Proof functions use version field. (MR :gl:`!4536`)

- Export context configuration. (MR :gl:`!4601`)

Liquidity Baking
----------------

Several changes are made to the Liquidity Baking Escape Vote (MR :gl:`!4201`):

- The options are renamed ``On`` (instead of ``false``) and ``Off``
  (instead of ``true``) to reduce confusion.

- A third ``Pass`` option is added. When this option is used the
  exponential moving average (EMA) of escape votes is not affected by
  the block. Note to developers of baking software: we don't recommend to
  use this option as a default value; instead we recommend to force the user
  to explicitly choose one of the three options; this behavior has been
  implemented in Octez' ``tezos-baker``.

- The escape hatch threshold is reset to 50% to account for the new
  symmetry in the escape vote introduced by ``Pass`` option.

- The precision of the EMA computation has been increased by a factor
  of 1000. To achieve this without overflowing, this computation is
  now performed using arbitrary-precision arithmetic. The EMA itself
  and the EMA threshold are still stored on 32bits.

- EMA is always rounded toward the threshold.

- When the EMA reaches the threshold, the deactivation of the subsidy
  is not permanent anymore. If the proportion of bakers voting ``On``
  later increases and the EMA falls back below the threshold then the
  subsidy is restarted.

- The Liquidity Baking Escape Vote is renamed into "Liquidity Baking
  Toggle Vote".

Transaction Optimistic Rollups
------------------------------

- Feature flag & origination. (MR :gl:`!3915`)

- Refactor the state type of Tx_rollup_repr. (MR :gl:`!4198`)

- Introduce the storage for inboxes. (MR :gl:`!4200`)

- Add the Tx_rollup_submit_batch operation. (MR :gl:`!4203`)

- Store a linked list of inbox levels. (MR :gl:`!4332`)

- Remove redundant size checks for messages. (MR :gl:`!4428`)

- Use EMA for fees_per_byte update. (MR :gl:`!4309`)

- Introduce the storage and context for the L2. (MR :gl:`!4360`)

- Introduce commitment repr and storage. (MR :gl:`!4369`)

- Various minor changes. (MR :gl:`!4447`)

- Node that tracks head and stores inboxes. (MR :gl:`!4357`)

- Add an optional burn limit to submit batch of L2 operations. (MR :gl:`!4344`)

- Fix and add regression tests. (MR :gl:`!4480`)

- Introduce L2 batches with compact encoding. (MR :gl:`!4275`)

- Deposit L1 tickets in the inbox. (MR :gl:`!4017`)

- Remove some node RPCs. (MR :gl:`!4489`)

- Make the appending of a message more predictable wrt gas consumption.
  (MR :gl:`!4499`)

- Use quantity abstraction for ticket amounts in the L2 context and batches.
  (MR :gl:`!4496`)

- Add succ and one for quantity abstraction. (MR :gl:`!4515`)

- Introduce the tx rollup layer2 apply function. (MR :gl:`!4453`)

- Switch to a one-commitment-per-level model. (MR :gl:`!4508`)

- Remove fixme. (MR :gl:`!4531`)

- Carbonate the hash of inbox messages. (MR :gl:`!4484`)

- Inbox hashes. (MR :gl:`!4495`)

- Commitment bond and finalization functions. (MR :gl:`!4446`)

- Allow commitments one block earlier. (MR :gl:`!4561`)

- Add tests to check batch limits. (MR :gl:`!4538`)

- Expect the counter's successor in operation. (MR :gl:`!4593`)

- Implement the complete life cycle of a transaction rollup. (MR :gl:`!4583`)

- Inbox message count limit. (MR :gl:`!4548`)

- Clean empty balance in the context. (MR :gl:`!4594`)

- Limit the number of finalized commitments. (MR :gl:`!4590`)

- Fix typos and improve code quality. (MR :gl:`!4603`)

- Check message hashes in the inbox. (MR :gl:`!4604`)

- Provide encodings for layer2 message results. (MR :gl:`!4576`)

- Layer2 implementation of layer2-to-layer1 withdrawal. (MR :gl:`!4517`)

- Batch JSON encoding with hexadecimal. (MR :gl:`!4572`)

- Make the simulation great again. (MR :gl:`!4634`)

- The payer is always an implicit contract. (MR :gl:`!4653`)

- Apply inboxes on transaction rollup L2 node context. (MR :gl:`!4521`)

- Add a test for a wrong rejection. (MR :gl:`!4649`)

- Clean-up the hash prefixes. (MR :gl:`!4668`)

Tickets Hardening
-----------------

- Tickets lazy storage diff. (MR :gl:`!4011`)

- Update tickets balances in migration to Alpha (MR :gl:`!3826`)

- Remove unused cost function (MR :gl:`!4303`)

- Ticket operations diff. (MR :gl:`!4168`)

- Break dependency between Ticket_hash_repr and Raw_context. (MR :gl:`!4323`)

- Tickets accounting module. (MR :gl:`!4334`)

- Add benchmark for cost_compare_ticket_hash. (MR :gl:`!4426`)

- Remaining tickets benchmarks. (MR :gl:`!4491`)

- Tickets accounting and enable feature. (MR :gl:`!4341`)

Smart Contract Optimistic Rollups
---------------------------------

- Add smart-contract rollup creation. (MR :gl:`!3941`)

- Add a smart contract rollup node. (MR :gl:`!4000`)

- Add Inbox. (MR :gl:`!4020`)

- Add storage of commitments. (MR :gl:`!4148`)

- Commitment logic. (MR :gl:`!4173`)

- RPC for listing all rollups. (MR :gl:`!4483`)

- Add L1 operation for cementing commitments. (MR :gl:`!4563`)

- Refactor commitment logic functions to fetch level from context.
  (MR :gl:`!4629`)

Voting procedure
----------------

The voting power of a delegate is no longer rounded to rolls, it is
now instead the full staking power of the delegate, currently
expressed in mutez. (MR :gl:`!4265`)

Breaking Changes
----------------

- The binary encoding of the result of the ``Transaction`` operation
  has changed.  Its contents now vary depending on the kind of
  destination. The default cases (implicit and smart contracts) are
  prefixed with the tag ``0``.

- The `consumed_gas` field in the encoding of operations becomes
  **deprecated** in favour of `consumed_milligas`, which contains
  a more precise readout for the same value. `consumed_milligas`
  field was added to the encoding of block metadata for uniformity.
  (MR :gl:`!4388`)

- The following RPCs output format changed:

  1. ``/chains/<chain_id>/blocks/<block>/votes/proposals``,
  2. ``/chains/<chain_id>/blocks/<block>/votes/ballots``,
  3. ``/chains/<chain_id>/blocks/<block>/votes/listings``,
  4. ``/chains/<chain_id>/blocks/<block>/votes/total_voting_power``,
  5. ``/chains/<chain_id>/blocks/<block>/context/delegates/<public_key_hash>``
  6. ``/chains/<chain_id>/blocks/<block>/context/delegates/<public_key_hash>/voting_power``

  The voting power that was represented by ``int32`` (denoting rolls)
  is now represented by an ``int64`` (denoting mutez). Furthermore, in
  the RPC ``/chains/<chain_id>/blocks/<block>/votes/listings``, the
  field ``rolls`` has been replaced by the field ``voting_power``.

- Encoding of transaction and origination operations no longer contains
  deprecated `big_map_diff` field. `lazy_storage_diff` should be used
  instead. (MR: :gl:`!4387`)

- The JSON and binary encodings for Liquidity Baking Toggle Votes have
  changed as follows:

.. list-table:: Changes to encodings of Liquidity Baking Toggle Vote
   :widths: 20 20 20 20 20
   :header-rows: 1

   * - Vote option
     - Old binary encoding
     - Old JSON encoding
     - New binary encoding
     - New JSON encoding

   * - ``On``
     - ``0x00``
     - ``false``
     - ``0x00``
     - ``"on"``

   * - ``Off``
     - any other byte
     - ``true``
     - ``0x01``
     - ``"off"``

   * - ``Pass``
     - N/A
     - N/A
     - ``0x02``
     - ``"pass"``

- The values of the Liquidity Baking EMA in block receipts and the
  Liquidity Baking EMA threshold in the constants have been scaled by
  1000, the new value of the threshold is 1,000,000,000. To compute
  the proportion Off/(On + Off) of toggle votes the following formula
  can be used: liquidity_baking_toggle_ema / 2,000,000,000.

Bug Fixes
---------

- Expose `consumed_milligas` in the receipt of the `Register_global_constant`
  operation. (MR :gl:`!3981`)

- Refuse operations with inconsistent counters. (MR :gl:`!4024`)

Minor Changes
-------------

- The RPC ``../context/delegates`` takes two additional Boolean flags
  ``with_minimal_stake`` and ``without_minimal_stake``, which allow to
  enumerate only the delegates that have at least a minimal stake to
  participate in consensus and in governance, or do not have such a
  minimal stake, respectively. (MR :gl:`!3951`)

- Make cache layout a parametric constant of the protocol. (MR :gl:`!4035`)

- Change ``blocks_per_voting period`` in context with ``cycles_per_voting_period`` (MR :gl:`!4456`)

Michelson
---------

- Some operations are now forbidden in views: ``CREATE_CONTRACT``,
  ``SET_DELEGATE`` and ``TRANSFER_TOKENS`` cannot be used at the top-level of a
  view because they are stateful, and ``SELF`` because the entry-point does not
  make sense in a view.
  However, ``CREATE_CONTRACT``, ``SET_DELEGATE`` and ``TRANSFER_TOKENS`` remain
  available in lambdas defined inside a view.
  (MR :gl:`!3737`)

- Stack variable annotations are ignored and not propagated. All contracts that
  used to typecheck correctly before will still typecheck correctly afterwards.
  Though more contracts are accepted as branches with different stack variable
  annotations won't be rejected any more.
  The special annotation ``%@`` of ``PAIR`` has no effect.
  RPCs ``typecheck_code``, ``trace_code``, as well as typechecking errors
  reporting stack types, won't report stack annotations any more.
  In their output encodings, the objects containing the fields ``item`` and
  ``annot`` are replaced with the contents of the field ``item``.
  (MR :gl:`!4139`)

- Variable annotations in pairs are ignored and not propagated.
  (MR :gl:`!4140`)

- Type annotations are ignored and not propagated.
  (MR :gl:`!4141`)

- Field annotations are ignored and not propagated.
  (MR :gl:`!4175`, :gl:`!4311`, :gl:`!4259`)

- Annotating the parameter toplevel constructor to designate the root entrypoint
  is now forbidden. Put the annotation on the parameter type instead.
  E.g. replace ``parameter %a int;`` by ``parameter (int %a);``
  (MR :gl:`!4366`)

- The ``VOTING_POWER`` of a contract is no longer rounded to rolls. It
  is now instead the full staking power of the delegate, currently
  expressed in mutez. Though, developers should not rely on
  ``VOTING_POWER`` to query the staking power of a contract in
  ``mutez``: the value returned by ``VOTING_POWER`` is still of type`
  ``nat`` and it should only be considered relative to
  ``TOTAL_VOTING_POWER``.

- The new type ``tx_rollup_l2_address`` has been introduced. It is
  used to identify accounts on transaction rollups’ legders. Values of
  type ``tx_rollup_l2_address`` are 20-byte hashes of a BLS
  public keys (with a string notation based of a base58 encoding,
  prefixed with ``tz4``). (MR :gl:`!4431`)

- A new instruction ``MIN_BLOCK_TIME`` has been added. It can be used to
  push the current minimal time between blocks onto the stack. The value is
  obtained from the protocol's ``minimal_block_delay`` constant.
  (MR :gl:`!4471`)

- The existing type ``sapling_transaction`` is renamed
  ``sapling_transaction_deprecated``. Existing onchain contracts are
  automatically converted.

RPC Changes
-----------

- Add ``selected_snapshot`` RPC that replaces deleted ``roll_snapshot``.
  (MRs :gl:`!4479`, :gl:`!4585`)

Internal
--------

The following changes are not visible to the users but reflect
improvements of the codebase.

- ``BALANCE`` is now passed to the Michelson interpreter as a step constant
  instead of being read from the context each time this instruction is
  executed. (MR :gl:`!3871`)

- Separate ``origination_nonce`` into its own module. (MR :gl:`!3928`)

- Faster gas monad. (MR :gl:`!4034`)

- Simplify cache limits for sampler state. (MR :gl:`!4041`)

- Tenderbrute - bruteforce seeds to obtain desired delegate selections in tests.
  (MR :gl:`!3842`)

- Clean Script_typed_ir_size.mli. (MR :gl:`!4088`)

- Improvements on merge type error flag. (MR :gl:`!3696`)

- Make entrypoint type abstract. (MR :gl:`!3755`)

- Make ``Slot_repr.t`` abstract. (MR :gl:`!4128`)

- Fix injectivity of types. (MR :gl:`!3863`)

- Split ``Ticket_storage`` in two and extract ``Ticket_hash_repr``.
  (MR :gl:`!4190`)

- Carbonated map utility module. (MR :gl:`!3845`)

- Extend carbonated-map with a fold operation. (MR :gl:`!4156`)

- Use dedicated error for duplicate ballots. (MR :gl:`!4209`)

- Rewrite step constants explicitly when entering a view. (MR :gl:`!4230`)

- Update migration for Ithaca. (MR :gl:`!4107`)

- Tenderbake: Optimizing round_and_offset. (MR :gl:`!4009`)

- Script_ir_translator: introduce Gas_monad into check_dupable_ty.
  (MR :gl:`!4262`)

- Address comments on the Tenderbake MR. (MR :gl:`!4225`)

- Make protocol easier to translate to Coq. (MR :gl:`!4260`)

- Introduce "add" function for Carbonated_data_set_storage. (MR :gl:`!4287`)

- Generalize the destination argument of Transaction. (MR :gl:`!4205`)

- Add missing mli for local-gas-counter module (MR :gl:`!4257`)

- Allow committee size to be < 4. (MR :gl:`!4308`)

- Do not propagate operations conditioned by a feature flag. (MR :gl:`!4330`)

- Make Gas.Arith.t type private. (MR :gl:`!4293`)

- Michelson: remove legacy behaviour in parse_toplevel (MR :gl:`!4364`)

- Michelson: carbonate find_entrypoint. (MR :gl:`!4363`)

- Michelson: remove metadata from basic types. (MR :gl:`!4297`)

- Optimize local gas counter exhaustion checking. (MR :gl:`!4305`)

- Give Script_ir_translator.type_logger argument explicit names.
  (MR :gl:`!4444`)

- Add Tenderbake unit tests and remove error messages from most unit tests.
  (MR :gl:`!4224`)

- Fix edge case in pseudorandom computations. (MR :gl:`!4385`)

- Ensure voting periods end at cycle ends. (MR :gl:`!4425`)

- Syntax module for the gas monad. (MR :gl:`!4432`)

- Michelson: simplify merge functions. (MR :gl:`!4298`)

- Remove Tenderbake-related legacy code. (MR :gl:`!4436`)

- Rename typ -> ty. (MR :gl:`!4468`)

- Gas: move Size module to lib_protocol. (MR :gl:`!4337`)

- Michelson: ensure completeness of type equality. (MR :gl:`!4427`)

- Cleanup Tenderbake code. (MR :gl:`!4423`)

- Fix coq:lint error ignoring message (MR :gl:`!4473`)

- Michelson: a few more annot cleanups. (MR :gl:`!4429`)

- Take user/automatic protocol upgrades into account during operation
  simulation. (MR :gl:`!4433`)

- Improve gas model of unparse_script. (MR :gl:`!4328`)

- Michelson: no comparable type in sets and maps. (MR :gl:`!4133`)

- Remove unreachable code (MR :gl:`!4615`)

- Michelson: move proof arguments. (MR :gl:`!4506`)

- Michelson: reduce elaborator garbage. (MR :gl:`!4578`)

- Michelson: GADTify stuff. (MR :gl:`!4507`)

- Michelson: preparation work to separate internal operations. (MR :gl:`!4613`)

- Michelson: rename sapling_transaction. (MR :gl:`!4670`)

- Michelson: move comparable ty smart constructors. (MR :gl:`!4658`)

- Other internal refactorings or documentation. (MRs :gl:`!4276`, `!4385`, `!4457`)
