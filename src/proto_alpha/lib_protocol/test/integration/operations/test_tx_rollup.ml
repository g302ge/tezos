(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2022 Oxhead Alpha <info@oxheadalpha.com>                    *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** Testing
    -------
    Component:    Rollup layer 1 logic
    Invocation:   cd src/proto_alpha/lib_protocol/test/integration/operations \
                  && dune exec ./main.exe -- test "^tx rollup$"
    Subject:      Test rollup
*)

open Protocol
open Alpha_context
open Test_tez

let empty_context_hash = Environment.Context_hash.zero

(** [check_tx_rollup_exists ctxt tx_rollup] returns [()] iff [tx_rollup]
    is a valid address for a transaction rollup. Otherwise, it fails. *)
let check_tx_rollup_exists ctxt tx_rollup =
  Context.Tx_rollup.state ctxt tx_rollup >|=? fun _ -> ()

(** [check_proto_error_f f t] checks that the first error of [t]
    satisfies the boolean function [f]. *)
let check_proto_error_f f t =
  match t with
  | Environment.Ecoproto_error e :: _ when f e ->
      Assert.test_error_encodings e ;
      return_unit
  | _ -> failwith "Unexpected error: %a" Error_monad.pp_print_trace t

let check_proto_error e = check_proto_error_f (( = ) e)

(** [test_disable_feature_flag] try to originate a tx rollup with the feature
    flag is deactivated and check it fails *)
let test_disable_feature_flag () =
  Context.init 1 >>=? fun (b, contracts) ->
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_origination (I i) contract >>=? fun (op, _tx_rollup) ->
  Incremental.add_operation
    ~expect_apply_failure:(check_proto_error Apply.Tx_rollup_feature_disabled)
    i
    op
  >>=? fun _i -> return_unit

let message_hash_testable : Tx_rollup_message.hash Alcotest.testable =
  Alcotest.testable Tx_rollup_message.pp_hash ( = )

let wrap m = m >|= Environment.wrap_tzresult

(** [inbox_burn state size] computes the burn (per byte of message)
    one has to pay to submit a message to the current inbox. *)
let inbox_burn state size =
  Environment.wrap_tzresult (Tx_rollup_state.burn_cost ~limit:None state size)

(** [burn_per_byte state] returns the cost to insert one byte inside
    the inbox. *)
let burn_per_byte state = inbox_burn state 1

(** [check_batch_in_inbox inbox n expected] checks that the [n]th
    element of [inbox] is a batch equal to [expected]. *)
let check_batch_in_inbox :
    t -> Tx_rollup_inbox.t -> int -> string -> unit tzresult Lwt.t =
 fun ctxt inbox n expected ->
  let (expected_batch, _) = Tx_rollup_message.make_batch expected in
  Environment.wrap_tzresult (Tx_rollup_message.hash ctxt expected_batch)
  >>?= fun (_ctxt, expected_hash) ->
  match List.nth inbox.contents n with
  | Some content ->
      Alcotest.(
        check
          message_hash_testable
          "Expected batch with a different content"
          content
          expected_hash) ;
      return_unit
  | _ -> Alcotest.fail "Selected message in the inbox is not a batch"

(** [context_init n] initializes a context with no consensus rewards
    to not interfere with balances prediction. It returns the created
    context and [n] contracts. *)
let context_init n =
  Context.init_with_constants
    {
      Context.default_test_contants with
      consensus_threshold = 0;
      tx_rollup_enable = true;
      tx_rollup_finality_period = 1;
      tx_rollup_withdraw_period = 1;
      tx_rollup_max_finalized_levels = 2;
      endorsing_reward_per_slot = Tez.zero;
      baking_reward_bonus_per_slot = Tez.zero;
      baking_reward_fixed_portion = Tez.zero;
    }
    n

(** [context_init1] initializes a context with no consensus rewards
    to not interfere with balances prediction. It returns the created
    context and 1 contract. *)
let context_init1 () =
  context_init 1 >|=? function
  | (b, contract_1 :: _) -> (b, contract_1)
  | (_, _) -> assert false

(** [context_init2] initializes a context with no consensus rewards
    to not interfere with balances prediction. It returns the created
    context and 2 contracts. *)
let context_init2 () =
  context_init 2 >|=? function
  | (b, contract_1 :: contract_2 :: _) -> (b, contract_1, contract_2)
  | (_, _) -> assert false

(** [originate b contract] originates a tx_rollup from [contract],
    and returns the new block and the tx_rollup address. *)
let originate b contract =
  Op.tx_rollup_origination (B b) contract >>=? fun (operation, tx_rollup) ->
  Block.bake ~operation b >>=? fun b -> return (b, tx_rollup)

(** Initializes the context, originates a tx_rollup and submits a batch.

    Returns the first contract and its balance, the originated tx_rollup,
    the state with the tx_rollup, and the baked block with the batch submitted.
*)
let init_originate_and_submit ?(batch = String.make 5 'c') () =
  context_init1 () >>=? fun (b, contract) ->
  originate b contract >>=? fun (b, tx_rollup) ->
  Context.Contract.balance (B b) contract >>=? fun balance ->
  Context.Tx_rollup.state (B b) tx_rollup >>=? fun state ->
  Op.tx_rollup_submit_batch (B b) contract tx_rollup batch >>=? fun operation ->
  Block.bake ~operation b >>=? fun b ->
  return ((contract, balance), state, tx_rollup, b)

let commitment_testable =
  Alcotest.testable Tx_rollup_commitment.pp Tx_rollup_commitment.( = )

let commitment_hash_testable =
  Alcotest.testable Tx_rollup_commitment_hash.pp Tx_rollup_commitment_hash.( = )

let public_key_hash_testable =
  Alcotest.testable Signature.Public_key_hash.pp Signature.Public_key_hash.( = )

let raw_level_testable = Alcotest.testable Raw_level.pp Raw_level.( = )

let inbox_hash_testable =
  Alcotest.testable Tx_rollup_inbox.pp_hash Tx_rollup_inbox.equal_hash

let rng_state = Random.State.make_self_init ()

let gen_l2_account () =
  let seed =
    Bytes.init 32 (fun _ -> char_of_int @@ Random.State.int rng_state 255)
  in
  let secret_key = Bls12_381.Signature.generate_sk seed in
  let public_key = Bls12_381.Signature.MinPk.derive_pk secret_key in
  (secret_key, public_key, Tx_rollup_l2_address.of_bls_pk public_key)

let is_implicit_exn x =
  match Alpha_context.Contract.is_implicit x with
  | Some x -> x
  | None -> raise (Invalid_argument "is_implicit_exn")

(** [make_ticket_key ty contents ticketer tx_rollup] computes the key hash
    of ticket crafted by [ticketer] and owned by [tx_rollup]. *)
let make_ticket_key ~ty ~contents ~ticketer tx_rollup =
  let open Tezos_micheline.Micheline in
  let ticketer =
    Bytes (0, Data_encoding.Binary.to_bytes_exn Contract.encoding ticketer)
  in
  match
    Alpha_context.Tx_rollup.Internal_for_tests.hash_ticket_uncarbonated
      ~ticketer
      ~ty
      ~contents
      tx_rollup
  with
  | Ok x -> x
  | Error _ -> raise (Invalid_argument "make_ticket_key")

(** [make_unit_ticket_key ticketer tx_rollup] computes the key hash of
    the unit ticket crafted by [ticketer] and owned by [tx_rollup]. *)
let make_unit_ticket_key ~ticketer tx_rollup =
  let open Tezos_micheline.Micheline in
  let open Michelson_v1_primitives in
  let ty = Prim (0, T_unit, [], []) in
  let contents = Prim (0, D_Unit, [], []) in
  make_ticket_key ~ty ~contents ~ticketer tx_rollup

let rng_state = Random.State.make_self_init ()

let print_deposit_arg tx_rollup account =
  let open Alpha_context.Script in
  Format.sprintf
    "Pair \"%s\" %s"
    (match tx_rollup with
    | `Typed pk -> Tx_rollup.to_b58check pk
    | `Raw str -> str)
    (match account with
    | `Hash pk -> Format.sprintf "\"%s\"" (Tx_rollup_l2_address.to_b58check pk)
    | `Raw str -> str)
  |> fun x ->
  Format.printf "%s\n@?" x ;
  x |> Expr.from_string |> lazy_expr

let assert_ok res = match res with Ok r -> r | Error _ -> assert false

let raw_level level = assert_ok @@ Raw_level.of_int32 level

let hash_empty_withdraw_list = Tx_rollup_withdraw.hash_list []

(* Make a valid commitment for a batch.  TODO/TORU: roots are still wrong, of
   course, until we get Merkle proofs In the mean time provides the list of
   withdraw in a association list of [batch_index -> withdraw_list].
   Be careful not to provide a too big withdraw_list as the construction
   is expensive *)
let make_commitment_for_batch ?(batches = []) i level tx_rollup withdraw_list =
  let ctxt = Incremental.alpha_ctxt i in
  wrap
    (Alpha_context.Tx_rollup_inbox.Internal_for_tests.get_metadata
       ctxt
       level
       tx_rollup)
  >>=? fun (ctxt, metadata) ->
  (if List.is_empty batches then
   List.init
     ~when_negative_length:[]
     (Int32.to_int metadata.inbox_length)
     (fun i -> Bytes.make 32 (Char.chr i))
  else Ok batches)
  >>?= fun batches_result ->
  let message_result =
    List.mapi
      (fun i v ->
        Tx_rollup_commitment.batch_commitment
          v
          (List.assq i withdraw_list |> Option.value ~default:[]
         |> Tx_rollup_withdraw.hash_list))
      batches_result
  in
  (match Tx_rollup_level.pred level with
  | None -> return_none
  | Some predecessor_level -> (
      wrap (Tx_rollup_commitment.find ctxt tx_rollup predecessor_level)
      >|=? function
      | (_, None) -> None
      | (_, Some {commitment; _}) -> Some (Tx_rollup_commitment.hash commitment)
      ))
  >>=? fun predecessor ->
  let commitment : Tx_rollup_commitment.t =
    {level; batches = message_result; predecessor; inbox_hash = metadata.hash}
  in
  return (commitment, batches_result)

let check_bond ctxt tx_rollup contract count =
  let pkh = is_implicit_exn contract in
  wrap (Tx_rollup_commitment.pending_bonded_commitments ctxt tx_rollup pkh)
  >>=? fun (_, pending) ->
  Alcotest.(check int "Pending bonded commitment count correct" count pending) ;
  return ()

let rec bake_until i top =
  let level = Incremental.level i in
  if level >= top then return i
  else
    Incremental.finalize_block i >>=? fun b ->
    Incremental.begin_construction b >>=? fun i -> bake_until i top

let assert_retired retired =
  match retired with
  | `Retired -> return_unit
  | _ -> failwith "Expected retired"

(** ---- TESTS -------------------------------------------------------------- *)

(** [test_origination] originates a transaction rollup and checks that
    it burns the expected quantity of xtz. *)
let test_origination () =
  Context.init ~tx_rollup_enable:true 1 >>=? fun (b, contracts) ->
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  Context.get_constants (B b)
  >>=? fun {parametric = {tx_rollup_origination_size; cost_per_byte; _}; _} ->
  Context.Contract.balance (B b) contract >>=? fun balance ->
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_origination (I i) contract >>=? fun (op, tx_rollup) ->
  Incremental.add_operation i op >>=? fun i ->
  check_tx_rollup_exists (I i) tx_rollup >>=? fun () ->
  cost_per_byte *? Int64.of_int tx_rollup_origination_size
  >>?= fun tx_rollup_origination_burn ->
  Assert.balance_was_debited
    ~loc:__LOC__
    (I i)
    contract
    balance
    tx_rollup_origination_burn

(** [test_two_originations] originates two transaction rollups in the
    same operation and checks that they have a different address. *)
let test_two_originations () =
  Context.init ~tx_rollup_enable:true 1 >>=? fun (b, contracts) ->
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_origination (I i) contract >>=? fun (op1, _false_tx_rollup1) ->
  (* tx_rollup1 and tx_rollup2 are equal and both are false. The addresses are
     derived from a value called `origination_nonce` that is dependent of the
     tezos operation hash. Also each origination increment this value.

     Here the origination_nonce is wrong because it's not based on the injected
     operation (the combined one. Also the used origination nonce is not
     incremented between _false_tx_rollup1 and _false_tx_rollup2 as the protocol
     do. *)
  Op.tx_rollup_origination (I i) contract >>=? fun (op2, _false_tx_rollup2) ->
  Op.combine_operations ~source:contract (B b) [op1; op2] >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  let nonce =
    Origination_nonce.Internal_for_tests.initial (Operation.hash_packed op)
  in
  let txo1 = Tx_rollup.Internal_for_tests.originated_tx_rollup nonce in
  let nonce = Origination_nonce.Internal_for_tests.incr nonce in
  let txo2 = Tx_rollup.Internal_for_tests.originated_tx_rollup nonce in
  Assert.not_equal
    ~loc:__LOC__
    Tx_rollup.equal
    "Two transaction rollups originated in one operation have different \
     addresses"
    Tx_rollup.pp
    txo1
    txo2
  >>=? fun () ->
  check_tx_rollup_exists (I i) txo1 >>=? fun () ->
  check_tx_rollup_exists (I i) txo2 >>=? fun () -> return_unit

(** [test_burn_per_byte_update] checks [update_burn_per_byte] behaves
    according to its docstring. *)
let test_burn_per_byte_update () =
  let test ~inbox_ema ~burn_per_byte ~final_size ~hard_limit ~result =
    let burn_per_byte = Tez.of_mutez_exn burn_per_byte in
    let result = Tez.of_mutez_exn result in
    let state =
      Alpha_context.Tx_rollup_state.Internal_for_tests.make
        ~burn_per_byte
        ~inbox_ema
        ()
    in
    let state =
      Alpha_context.Tx_rollup_state.Internal_for_tests.update_burn_per_byte
        state
        ~final_size
        ~hard_limit
    in
    let new_burn =
      match Alpha_context.Tx_rollup_state.burn_cost ~limit:None state 1 with
      | Ok x -> x
      | Error _ ->
          Stdlib.failwith "could not compute the fees for a message of 1 byte"
    in
    Assert.equal_tez ~loc:__LOC__ result new_burn
  in

  (* Fees per byte should remain constant *)
  test
    ~inbox_ema:1_000
    ~burn_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_100
    ~result:1_000L
  >>=? fun () ->
  (* Fees per byte should increase *)
  test
    ~inbox_ema:1_000
    ~burn_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_000
    ~result:1_050L
  >>=? fun () ->
  (* Fees per byte should decrease *)
  test
    ~inbox_ema:1_000
    ~burn_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_500
    ~result:950L
  >>=? fun () ->
  (* Fees per byte should increase even with [0] as its initial value *)
  test
    ~inbox_ema:1_000
    ~burn_per_byte:0L
    ~final_size:1_000
    ~hard_limit:1_000
    ~result:1L
  >>=? fun () -> return_unit

(** [test_add_batch] originates a tx rollup and fills one of its inbox
    with an arbitrary batch of data. *)
let test_add_batch () =
  let contents_size = 5 in
  let contents = String.make contents_size 'c' in
  init_originate_and_submit ~batch:contents ()
  >>=? fun ((contract, balance), state, tx_rollup, b) ->
  Context.Tx_rollup.inbox (B b) tx_rollup Tx_rollup_level.root
  >>=? fun {contents; cumulated_size; hash} ->
  let length = List.length contents in
  let expected_hash =
    Tx_rollup_inbox.hash_of_b58check_exn
      "i3smFXyzYSSsi14AwTBJ9xqV2CvYajp6cUzPFRshWeLoUB942Kw"
  in
  Alcotest.(check int "Expect an inbox with a single item" 1 length) ;
  Alcotest.(check int "Expect cumulated size" contents_size cumulated_size) ;
  Alcotest.(check inbox_hash_testable "Expect hash" expected_hash hash) ;
  inbox_burn state contents_size >>?= fun cost ->
  Assert.balance_was_debited ~loc:__LOC__ (B b) contract balance cost

let test_add_batch_with_limit () =
  (* From an empty context the burn will be [Tez.zero], we set the hard limit to
     [Tez.zero], so [cost] >= [limit] *)
  let burn_limit = Tez.zero in
  let contents = String.make 5 'd' in
  context_init1 () >>=? fun (b, contract) ->
  originate b contract >>=? fun (b, tx_rollup) ->
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_submit_batch (I i) contract tx_rollup contents ~burn_limit
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f (function
          | Tx_rollup_errors.Submit_batch_burn_excedeed _ -> true
          | _ -> false))
  >>=? fun _ -> return_unit

(** [test_add_two_batches] originates a tx rollup and adds two
    arbitrary batches to one of its inboxes. Ensure that their order
    is correct. *)
let test_add_two_batches () =
  (*
    TODO: https://gitlab.com/tezos/tezos/-/issues/2331
    This test can be generalized using a property-based approach.
   *)
  let contents_size1 = 5 in
  let contents1 = String.make contents_size1 'c' in
  init_originate_and_submit ~batch:contents1 ()
  >>=? fun ((contract, balance), state, tx_rollup, b) ->
  Op.tx_rollup_submit_batch (B b) contract tx_rollup contents1 >>=? fun op1 ->
  Context.Contract.counter (B b) contract >>=? fun counter ->
  let contents_size2 = 6 in
  let contents2 = String.make contents_size2 'd' in
  Op.tx_rollup_submit_batch
    ~counter:Z.(add counter (of_int 1))
    (B b)
    contract
    tx_rollup
    contents2
  >>=? fun op2 ->
  Block.bake ~operations:[op1; op2] b >>=? fun b ->
  (* There were a first inbox with one message, and we are looking for
     its successor. *)
  Context.Tx_rollup.inbox (B b) tx_rollup Tx_rollup_level.(succ root)
  >>=? fun inbox ->
  let length = List.length inbox.contents in
  let expected_cumulated_size = contents_size1 + contents_size2 in

  Alcotest.(check int "Expect an inbox with two items" 2 length) ;
  Alcotest.(
    check
      int
      "Expect cumulated size"
      expected_cumulated_size
      inbox.cumulated_size) ;

  Incremental.begin_construction b >>=? fun incr ->
  let ctxt = Incremental.alpha_ctxt incr in
  check_batch_in_inbox ctxt inbox 0 contents1 >>=? fun () ->
  check_batch_in_inbox ctxt inbox 1 contents2 >>=? fun () ->
  inbox_burn state expected_cumulated_size >>?= fun cost ->
  Assert.balance_was_debited ~loc:__LOC__ (B b) contract balance cost

(** Try to add a batch too large in an inbox. *)
let test_batch_too_big () =
  context_init1 () >>=? fun (b, contract) ->
  originate b contract >>=? fun (b, tx_rollup) ->
  Context.get_constants (B b) >>=? fun constant ->
  let contents =
    String.make
      (constant.parametric.tx_rollup_hard_size_limit_per_message + 1)
      'd'
  in
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_submit_batch (I i) contract tx_rollup contents >>=? fun op ->
  Incremental.add_operation
    i
    ~expect_apply_failure:
      (check_proto_error Tx_rollup_errors.Message_size_exceeds_limit)
    op
  >>=? fun _ -> return_unit

(** [fill_inbox b tx_rollup contract contents k] fills the inbox of
    [tx_rollup] with batches containing [contents] sent by [contract].
    Before exceeding the limit size of the inbox, the continuation [k]
    is called with two parameters: the incremental state of the block
    with the almost full inboxes, and an operation that would cause an
    error if applied. *)
let fill_inbox b tx_rollup contract contents k =
  let message_size = String.length contents in
  Context.get_constants (B b) >>=? fun constant ->
  let tx_rollup_inbox_limit =
    constant.parametric.tx_rollup_hard_size_limit_per_inbox
  in
  Context.Contract.counter (B b) contract >>=? fun counter ->
  Incremental.begin_construction b >>=? fun i ->
  let rec fill_inbox i inbox_size counter =
    (* By default, the [gas_limit] is the maximum gas that can be
       consumed by an operation. We set a lower (arbitrary) limit to
       be able to reach the size limit of an operation. *)
    Op.tx_rollup_submit_batch
      ~gas_limit:(Gas.Arith.integral_of_int_exn 100_000)
      ~counter
      (I i)
      contract
      tx_rollup
      contents
    >>=? fun op ->
    let new_inbox_size = inbox_size + message_size in
    if new_inbox_size < tx_rollup_inbox_limit then
      Incremental.add_operation i op >>=? fun i ->
      fill_inbox i new_inbox_size (Z.succ counter)
    else k i inbox_size op
  in

  fill_inbox i 0 counter

(** Try to add enough large batches to reach the size limit of an inbox. *)
let test_inbox_size_too_big () =
  context_init1 () >>=? fun (b, contract) ->
  Context.get_constants (B b) >>=? fun constant ->
  let tx_rollup_batch_limit =
    constant.parametric.tx_rollup_hard_size_limit_per_message - 1
  in
  let contents = String.make tx_rollup_batch_limit 'd' in
  originate b contract >>=? fun (b, tx_rollup) ->
  fill_inbox b tx_rollup contract contents (fun i _ op ->
      Incremental.add_operation
        i
        op
        ~expect_failure:
          (check_proto_error_f (function
              | Tx_rollup_errors.Inbox_size_would_exceed_limit _ -> true
              | _ -> false))
      >>=? fun _i -> return_unit)

(** Try to add enough batches to reach the batch count limit of an inbox. *)
let test_inbox_count_too_big () =
  context_init1 () >>=? fun (b, contract) ->
  Context.get_constants (B b) >>=? fun constant ->
  let message_count = constant.parametric.tx_rollup_max_messages_per_inbox in
  let contents = "some contents" in
  originate b contract >>=? fun (b, tx_rollup) ->
  Incremental.begin_construction b >>=? fun i ->
  let rec fill_inbox i counter n =
    (* By default, the [gas_limit] is the maximum gas that can be
       consumed by an operation. We set a lower (arbitrary) limit to
       be able to reach the size limit of an operation. *)
    Op.tx_rollup_submit_batch
      ~gas_limit:(Gas.Arith.integral_of_int_exn 2_500)
      ~counter
      (I i)
      contract
      tx_rollup
      contents
    >>=? fun op ->
    if n > 0 then
      Incremental.add_operation i op >>=? fun i ->
      fill_inbox i (Z.succ counter) (n - 1)
    else return (i, counter)
  in
  Context.Contract.counter (B b) contract >>=? fun counter ->
  fill_inbox i counter message_count >>=? fun (i, counter) ->
  Op.tx_rollup_submit_batch
    ~gas_limit:(Gas.Arith.integral_of_int_exn 2_500)
    ~counter
    (I i)
    contract
    tx_rollup
    contents
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f @@ function
       | Tx_rollup_errors.Inbox_count_would_exceed_limit rollup ->
           rollup = tx_rollup
       | _ -> false)
  >>=? fun i ->
  ignore i ;
  return ()

(** [test_valid_deposit] checks that a smart contract can deposit
    tickets to a transaction rollup. *)
let test_valid_deposit () =
  let (_, _, pkh) = gen_l2_account () in

  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  let parameters = print_deposit_arg (`Typed tx_rollup) (`Hash pkh) in
  let fee = Test_tez.of_int 10 in
  Op.transaction
    ~counter:(Z.of_int 2)
    ~fee
    (B b)
    account
    contract
    Tez.zero
    ~parameters
  >>=? fun operation ->
  Block.bake ~operation b >>=? fun b ->
  Incremental.begin_construction b >|=? Incremental.alpha_ctxt >>=? fun ctxt ->
  Context.Tx_rollup.inbox (B b) tx_rollup Tx_rollup_level.root >>=? function
  | {contents = [hash]; _} ->
      let ticket_hash = make_unit_ticket_key ~ticketer:contract tx_rollup in
      let (message, _size) =
        Tx_rollup_message.make_deposit
          (is_implicit_exn account)
          (Tx_rollup_l2_address.Indexable.value pkh)
          ticket_hash
          (Tx_rollup_l2_qty.of_int64_exn 10L)
      in
      Environment.wrap_tzresult (Tx_rollup_message.hash ctxt message)
      >>?= fun (_ctxt, expected) ->
      Alcotest.(check message_hash_testable "deposit" hash expected) ;
      return_unit
  | _ -> Alcotest.fail "The inbox has not the expected shape"

(** [test_valid_deposit_inexistant_rollup] checks that the Michelson
    interpreter checks the existence of a transaction rollup prior to
    sending a deposit order. *)
let test_valid_deposit_inexistant_rollup () =
  let (_, _, pkh) = gen_l2_account () in
  context_init1 () >>=? fun (b, account) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  Incremental.begin_construction b >>=? fun i ->
  let parameters =
    print_deposit_arg (`Raw "tru1HdK6HiR31Xo1bSAr4mwwCek8ExgwuUeHm") (`Hash pkh)
  in
  let fee = Test_tez.of_int 10 in
  Op.transaction ~fee (I i) account contract Tez.zero ~parameters >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f (function
          | Script_interpreter.Runtime_contract_error _ -> true
          | _ -> false))
  >>=? fun _ -> return_unit

(** [test_invalid_deposit_not_contract] checks a smart contract cannot
    deposit something that is not a ticket. *)
let test_invalid_deposit_not_ticket () =
  let (_, _, pkh) = gen_l2_account () in

  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit_incorrect_param.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  Incremental.begin_construction b >>=? fun i ->
  let parameters = print_deposit_arg (`Typed tx_rollup) (`Hash pkh) in
  let fee = Test_tez.of_int 10 in
  Op.transaction ~fee (I i) account contract Tez.zero ~parameters >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f (function
          | Script_interpreter.Bad_contract_parameter _ -> true
          | _ -> false))
  >>=? fun _ -> return_unit

(** [test_invalid_entrypoint] checks that a transaction to an invalid entrypoint
    of a transaction rollup fails. *)
let test_invalid_entrypoint () =
  let (_, _, pkh) = gen_l2_account () in

  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit_incorrect_param.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  Incremental.begin_construction b >>=? fun i ->
  let parameters = print_deposit_arg (`Typed tx_rollup) (`Hash pkh) in
  let fee = Test_tez.of_int 10 in
  Op.transaction ~fee (I i) account contract Tez.zero ~parameters >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f (function
          | Script_interpreter.Bad_contract_parameter _ -> true
          | _ -> false))
  >>=? fun _ -> return_unit

(** [test_invalid_l2_address] checks that a smart contract cannot make
    a deposit order to something that is not a valid layer-2 address. *)
let test_invalid_l2_address () =
  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  Incremental.begin_construction b >>=? fun i ->
  let parameters =
    print_deposit_arg (`Typed tx_rollup) (`Raw "\"invalid L2 address\"")
  in
  let fee = Test_tez.of_int 10 in
  Op.transaction ~fee (I i) account contract Tez.zero ~parameters >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f (function
          | Script_interpreter.Bad_contract_parameter _ -> true
          | _ -> false))
  >>=? fun _ -> return_unit

(** [test_valid_deposit_invalid_amount] checks that a transaction to a
    transaction rollup fails if the [amount] parameter is not null. *)
let test_valid_deposit_invalid_amount () =
  let (_, _, pkh) = gen_l2_account () in
  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Contract_helpers.originate_contract
    "contracts/tx_rollup_deposit_one_mutez.tz"
    "Unit"
    account
    b
    (is_implicit_exn account)
  >>=? fun (contract, b) ->
  Incremental.begin_construction b >>=? fun i ->
  let parameters = print_deposit_arg (`Typed tx_rollup) (`Hash pkh) in
  let fee = Test_tez.of_int 10 in
  Op.transaction ~fee (I i) account contract Tez.zero ~parameters >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error Apply.Tx_rollup_invalid_transaction_amount)
  >>=? fun _ -> return_unit

(** [test_deposit_by_non_internal_operation] checks that a transaction
    to the deposit entrypoint of a transaction rollup fails if it is
    not internal. *)
let test_deposit_by_non_internal_operation () =
  context_init1 () >>=? fun (b, account) ->
  originate b account >>=? fun (b, tx_rollup) ->
  Op.unsafe_transaction (B b) account (Tx_rollup tx_rollup) Tez.zero
  >>=? fun operation ->
  Incremental.begin_construction b >>=? fun i ->
  Incremental.add_operation
    i
    operation
    ~expect_failure:(check_proto_error Apply.Tx_rollup_non_internal_transaction)
  >>=? fun _i -> return_unit

(** Test that block finalization changes gas rates *)
let test_finalization () =
  context_init 2 >>=? fun (b, contracts) ->
  (* TODO: should [filler] and [contract] really be the same? *)
  let filler = WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0 in
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  originate b contract >>=? fun (b, tx_rollup) ->
  Context.get_constants (B b)
  >>=? fun {parametric = {tx_rollup_hard_size_limit_per_inbox; _}; _} ->
  (* Get the initial burn_per_byte. *)
  Context.Tx_rollup.state (B b) tx_rollup >>=? fun state ->
  burn_per_byte state >>?= fun cost ->
  Assert.equal_tez ~loc:__LOC__ Tez.zero cost >>=? fun () ->
  (* Fill the inbox. *)
  Context.get_constants (B b) >>=? fun constant ->
  let tx_rollup_batch_limit =
    constant.parametric.tx_rollup_hard_size_limit_per_message - 1
  in
  let contents = String.make tx_rollup_batch_limit 'd' in

  (* Repeating fill inbox and finalize block to increase EMA
     until EMA is enough to provoke a change of fees. *)
  let rec increase_ema n b tx_rollup f =
    f b tx_rollup >>=? fun (inbox_size, i) ->
    Incremental.finalize_block i >>=? fun b ->
    Context.Tx_rollup.state (B b) tx_rollup >>=? fun state ->
    let inbox_ema =
      Alpha_context.Tx_rollup_state.Internal_for_tests.get_inbox_ema state
    in
    if tx_rollup_hard_size_limit_per_inbox * 91 / 100 < inbox_ema then
      return (b, n, inbox_size)
    else increase_ema (n + 1) b tx_rollup f
  in
  ( increase_ema 1 b tx_rollup @@ fun b tx_rollup ->
    fill_inbox b tx_rollup filler contents (fun i size _ -> return (size, i)) )
  >>=? fun (b, n, inbox_size) ->
  let rec update_burn_per_byte_n_time n state =
    if n > 0 then
      let state =
        Alpha_context.Tx_rollup_state.Internal_for_tests.update_burn_per_byte
          state
          ~final_size:inbox_size
          ~hard_limit:tx_rollup_hard_size_limit_per_inbox
      in
      update_burn_per_byte_n_time (n - 1) state
    else state
  in
  (* Check the fees we are getting after finalization are (1) strictly
     positive, and (2) the one we can predict with
     [update_burn_per_byte]. *)
  let expected_state = update_burn_per_byte_n_time n state in
  burn_per_byte expected_state >>?= fun expected_burn_per_byte ->
  Context.Tx_rollup.state (B b) tx_rollup >>=? fun state ->
  burn_per_byte state >>?= fun burn_per_byte ->
  assert (Tez.(zero < burn_per_byte)) ;
  Assert.equal_tez ~loc:__LOC__ expected_burn_per_byte burn_per_byte
  >>=? fun () ->
  (* Insert a small batch in a new block *)
  let contents_size = 5 in
  let contents = String.make contents_size 'c' in
  Context.Contract.balance (B b) contract >>=? fun balance ->
  Context.Contract.counter (B b) contract >>=? fun counter ->
  Op.tx_rollup_submit_batch ~counter (B b) contract tx_rollup contents
  >>=? fun op ->
  Block.bake b ~operation:op >>=? fun b ->
  (* Predict the cost we had to pay. *)
  inbox_burn state contents_size >>?= fun cost ->
  Assert.balance_was_debited ~loc:__LOC__ (B b) contract balance cost

(** [test_commitment_duplication] originates a rollup, and makes a
    commitment. It attempts to add a second commitment for the same
    level, and ensures that this fails.  It adds a commitment with
    the wrong batch count and ensures that that fails. *)
let test_commitment_duplication () =
  context_init2 () >>=? fun (b, contract1, contract2) ->
  let pkh1 = is_implicit_exn contract1 in
  originate b contract1 >>=? fun (b, tx_rollup) ->
  Context.Contract.balance (B b) contract1 >>=? fun _balance ->
  Context.Contract.balance (B b) contract2 >>=? fun balance2 ->
  (* In order to have a permissible commitment, we need a transaction. *)
  let contents = "batch" in
  Op.tx_rollup_submit_batch (B b) contract1 tx_rollup contents
  >>=? fun operation ->
  Block.bake ~operation b >>=? fun b ->
  Incremental.begin_construction b >>=? fun i ->
  make_commitment_for_batch i Tx_rollup_level.root tx_rollup []
  >>=? fun (commitment, _) ->
  (* Successfully fail to submit a different commitment from contract2 *)
  let batches2 =
    [Bytes.make 20 '1'; Bytes.make 20 '2']
    |> List.map (fun context_hash ->
           Tx_rollup_commitment.batch_commitment
             context_hash
             hash_empty_withdraw_list)
  in
  let commitment_with_wrong_count : Tx_rollup_commitment.t =
    {commitment with batches = batches2}
  in
  Op.tx_rollup_commit (I i) contract2 tx_rollup commitment_with_wrong_count
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:(check_proto_error Tx_rollup_errors.Wrong_batch_count)
  >>=? fun i ->
  (* Submit the correct one *)
  let submitted_level = (Level.current (Incremental.alpha_ctxt i)).level in
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  (* TODO/TORU: https://gitlab.com/tezos/tezos/-/merge_requests/4437 *)
  (* let cost = Tez.of_mutez_exn 10_000_000_000L in *)
  (* Assert.balance_was_debited ~loc:__LOC__ (I i) contract1 balance cost *)
  (* >>=? fun () -> *)
  (* Successfully fail to submit a duplicate commitment *)
  Op.tx_rollup_commit (I i) contract2 tx_rollup commitment >>=? fun op ->
  (Incremental.add_operation i op >>= function
   | Ok _ -> failwith "an error was expected"
   | Error e ->
       check_proto_error_f
         (function
           | Tx_rollup_errors.Level_already_has_commitment level1 ->
               Tx_rollup_level.root = level1
           | _ -> false)
         e)
  >>=? fun _ ->
  (* No charge. *)
  Assert.balance_was_debited ~loc:__LOC__ (I i) contract2 balance2 Tez.zero
  >>=? fun () ->
  let ctxt = Incremental.alpha_ctxt i in
  wrap (Tx_rollup_commitment.find ctxt tx_rollup Tx_rollup_level.root)
  >>=? fun (_, commitment_opt) ->
  (match commitment_opt with
  | None -> raise (Invalid_argument "No commitment")
  | Some
      {
        commitment = expected_commitment;
        commitment_hash = expected_hash;
        committer;
        submitted_at;
        finalized_at;
      } ->
      Alcotest.(
        check commitment_testable "Commitment" expected_commitment commitment) ;
      Alcotest.(
        check commitment_hash_testable "Commitment hash" expected_hash
        @@ Tx_rollup_commitment.hash commitment) ;
      Alcotest.(check public_key_hash_testable "Committer" pkh1 committer) ;
      Alcotest.(
        check raw_level_testable "Submitted" submitted_level submitted_at) ;
      Alcotest.(check (option raw_level_testable) "Finalized" None finalized_at)) ;
  check_bond ctxt tx_rollup contract1 1 >>=? fun () ->
  check_bond ctxt tx_rollup contract2 0 >>=? fun () ->
  ignore i ;
  return ()

let make_transactions_in tx_rollup contract blocks b =
  let contents = "batch " in
  let rec aux cur blocks b =
    match blocks with
    | [] -> return b
    | hd :: rest when hd = cur ->
        Op.tx_rollup_submit_batch (B b) contract tx_rollup contents
        >>=? fun operation ->
        Block.bake ~operation b >>=? fun b -> aux (cur + 1) rest b
    | blocks ->
        let operations = [] in
        Block.bake ~operations b >>=? fun b -> aux (cur + 1) blocks b
  in
  aux 2 blocks b

let assert_ok res =
  match res with
  | Ok r -> r
  | Error _ -> raise (Invalid_argument "Error: assert_ok")

let tx_level level = assert_ok @@ Tx_rollup_level.of_int32 level

(** [test_commitment_predecessor] tests commitment predecessor edge cases  *)
let test_commitment_predecessor () =
  context_init1 () >>=? fun (b, contract1) ->
  originate b contract1 >>=? fun (b, tx_rollup) ->
  (* Transactions in blocks 2, 3, 6 *)
  make_transactions_in tx_rollup contract1 [2; 3; 6] b >>=? fun b ->
  Incremental.begin_construction b >>=? fun i ->
  (* Check error: Commitment for nonexistent block *)
  let bogus_hash =
    Tx_rollup_commitment_hash.of_bytes_exn
      (Bytes.of_string "tcu1deadbeefdeadbeefdeadbeefdead")
  in
  make_commitment_for_batch i Tx_rollup_level.root tx_rollup []
  >>=? fun (commitment, _) ->
  let commitment_for_invalid_inbox = {commitment with level = tx_level 10l} in
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment_for_invalid_inbox
  >>=? fun op ->
  let error =
    Tx_rollup_errors.Commitment_too_early
      {provided = tx_level 10l; expected = tx_level 0l}
  in
  Incremental.add_operation i op ~expect_apply_failure:(check_proto_error error)
  >>=? fun _ ->
  (* Now we submit a real commitment *)
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  (* Commitment without predecessor for block with predecessor*)
  make_commitment_for_batch i Tx_rollup_level.(succ root) tx_rollup []
  >>=? fun (commitment, _) ->
  let commitment_with_missing_predecessor =
    {commitment with predecessor = None}
  in
  Op.tx_rollup_commit
    (I i)
    contract1
    tx_rollup
    commitment_with_missing_predecessor
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f @@ function
       | Tx_rollup_errors.Wrong_predecessor_hash {provided = None; expected} ->
           expected = commitment.predecessor
       | _ -> false)
  >>=? fun i ->
  (* Commitment refers to a predecessor which does not exist *)
  let commitment_with_wrong_pred =
    {commitment with predecessor = Some bogus_hash}
  in
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment_with_wrong_pred
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f @@ function
       | Tx_rollup_errors.Wrong_predecessor_hash {provided = _; expected} ->
           expected = commitment.predecessor
       | _ -> false)
  >>=? fun i ->
  ignore i ;
  return ()

let test_full_inbox () =
  let constants =
    {
      Tezos_protocol_alpha_parameters.Default_parameters.constants_test with
      consensus_threshold = 0;
      endorsing_reward_per_slot = Tez.zero;
      baking_reward_bonus_per_slot = Tez.zero;
      baking_reward_fixed_portion = Tez.zero;
      tx_rollup_enable = true;
      tx_rollup_max_unfinalized_levels = 15;
    }
  in
  Context.init_with_constants constants 1 >>=? fun (b, contracts) ->
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  originate b contract >>=? fun (b, tx_rollup) ->
  let range start top =
    let rec aux n acc = if n < start then acc else aux (n - 1) (n :: acc) in
    aux top []
  in
  (* Transactions in blocks [2..17) *)
  make_transactions_in tx_rollup contract (range 2 17) b >>=? fun b ->
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_submit_batch (B b) contract tx_rollup "contents" >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:(check_proto_error Tx_rollup_errors.Too_many_inboxes)
  >>=? fun i ->
  ignore i ;
  return ()

(** [test_bond_finalization] tests that level retirement in fact
    allows bonds to be returned. *)
let test_bond_finalization () =
  context_init1 () >>=? fun (b, contract1) ->
  let pkh1 = is_implicit_exn contract1 in
  originate b contract1 >>=? fun (b, tx_rollup) ->
  (* Transactions in block 2, 3, 4 *)
  make_transactions_in tx_rollup contract1 [2; 3; 4] b >>=? fun b ->
  (* Let’s try to remove the bond *)
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_return_bond (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f @@ function
       | Tx_rollup_errors.Bond_does_not_exist a_pkh1 -> a_pkh1 = pkh1
       | _ -> false)
  >>=? fun i ->
  make_commitment_for_batch i Tx_rollup_level.root tx_rollup []
  >>=? fun (commitment_a, _) ->
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment_a >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  Op.tx_rollup_return_bond (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error_f @@ function
       | Tx_rollup_errors.Bond_in_use a_pkh1 -> a_pkh1 = pkh1
       | _ -> false)
  >>=? fun i ->
  Incremental.finalize_block i >>=? fun b ->
  (* Finalize the commitment of level 0. *)
  Op.tx_rollup_finalize (B b) contract1 tx_rollup >>=? fun operation ->
  Block.bake b ~operation >>=? fun b ->
  (* Bake enough block, and remove the commitment of level 0. *)
  Block.bake b ~operations:[] >>=? fun b ->
  Op.tx_rollup_remove_commitment (B b) contract1 tx_rollup >>=? fun operation ->
  Block.bake b ~operation >>=? fun b ->
  (* Try to return the bond *)
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_return_bond (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation i op >>=? fun _ ->
  (* TODO/TORU: https://gitlab.com/tezos/tezos/-/merge_requests/4437
     Once stakable bonds are merged, check the balances. *)
  return ()

(** [test_too_many_commitments] tests that you can't submit new
      commitments if there are too many finalized commitments. *)
let test_too_many_commitments () =
  context_init1 () >>=? fun (b, contract1) ->
  originate b contract1 >>=? fun (b, tx_rollup) ->
  (* Transactions in block 2, 3, 4, 5 *)
  make_transactions_in tx_rollup contract1 [2; 3; 4; 5] b >>=? fun b ->
  Incremental.begin_construction b >>=? fun i ->
  let rec make_commitments i level n =
    if n = 0 then return (i, level)
    else
      make_commitment_for_batch i level tx_rollup [] >>=? fun (commitment, _) ->
      Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
      Incremental.add_operation i op >>=? fun i ->
      make_commitments i (Tx_rollup_level.succ level) (n - 1)
  in
  make_commitments i Tx_rollup_level.root 3 >>=? fun (i, level) ->
  (* Make sure all commitments can be finalized. *)
  bake_until i 10l >>=? fun i ->
  Op.tx_rollup_finalize (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  Op.tx_rollup_finalize (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  (* Fail to add a new commitment. *)
  make_commitment_for_batch i level tx_rollup [] >>=? fun (commitment, _) ->
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:
      (check_proto_error Tx_rollup_errors.Too_many_finalized_commitments)
  >>=? fun i ->
  (* Wait out the withdrawal period. *)
  bake_until i 12l >>=? fun i ->
  (* Remove one finalized commitment. *)
  Op.tx_rollup_remove_commitment (I i) contract1 tx_rollup >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  (* Now we can add a new commitment. *)
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  ignore i ;

  return ()

module Withdraw = struct
  (** [context_init_withdraw n] initializes a context with [n + 1] accounts, one rollup and a
      withdrawal recipient contract. *)
  let context_init_withdraw n =
    context_init (n + 1) >>=? fun (b, accounts) ->
    let account1 =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth accounts 0
    in
    originate b account1 >>=? fun (b, tx_rollup) ->
    Contract_helpers.originate_contract
      "contracts/tx_rollup_withdraw.tz"
      "None"
      account1
      b
      (is_implicit_exn account1)
    >>=? fun (withdraw_contract, b) ->
    return (account1, accounts, tx_rollup, withdraw_contract, b)

  (** [context_init1_withdraw] initializes a context with one account, one rollup and a
      withdrawal recipient contract. *)
  let context_init1_withdraw () =
    context_init_withdraw 0
    >>=? fun (account1, _accounts, tx_rollup, withdraw_contract, b) ->
    return (account1, tx_rollup, withdraw_contract, b)

  (** [context_init2_withdraw] initializes a context with two accounts, one rollup and a
      withdrawal recipient contract. *)
  let context_init2_withdraw () =
    context_init_withdraw 1
    >>=? fun (account1, accounts, tx_rollup, withdraw_contract, b) ->
    let account2 =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth accounts 1
    in
    return (account1, account2, tx_rollup, withdraw_contract, b)

  (** [context_finalize_batch_with_withdrawals account tx_rollup batch withdrawals b]
      submits a batch containing the message [batch] to [tx_rollup] in the block [b].
      In the following block, it adds a commitment for that block containing
      [withdrawals] (same format as in [make_commitment_for_batch]).
      In the third and final block, it finalizes the commitment.

      It returns the commitment and a list of dummy context hashes
      that was mocked as the result of the applying the batch.
   *)
  let context_finalize_batch_with_withdrawals ~account ~tx_rollup
      ?(batch = "batch") ~withdrawals b =
    Op.tx_rollup_submit_batch (B b) account tx_rollup batch
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* Make a commitment for the dummy batch. Mock the
       list of withdrawals as per
       [withdrawals]. Include the commitment in an operation and bake. *)
    Incremental.begin_construction b >>=? fun i ->
    make_commitment_for_batch i Tx_rollup_level.root tx_rollup withdrawals
    >>=? fun (commitment, context_hash_list) ->
    Op.tx_rollup_commit (I i) account tx_rollup commitment >>=? fun operation ->
    Incremental.add_operation i operation >>=? fun i ->
    Incremental.finalize_block i >>=? fun b ->
    (* 3. Finalize the commitment *)
    Op.tx_rollup_finalize (B b) account tx_rollup >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    return (commitment, context_hash_list, b)

  module Nat_ticket = struct
    let ty = Expr.from_string "nat"

    let contents_nat = 1

    let contents = Expr.from_string (string_of_int contents_nat)

    let amount = Tx_rollup_l2_qty.of_int64_exn 10L

    let ticket_hash ~ticketer ~tx_rollup =
      make_ticket_key
        ~ty:(Tezos_micheline.Micheline.root ty)
        ~contents:(Tezos_micheline.Micheline.root contents)
        ~ticketer
        tx_rollup

    let withdrawal ~ticketer ?(recipient = ticketer) tx_rollup :
        Tx_rollup_withdraw.t =
      {
        destination = is_implicit_exn recipient;
        ticket_hash = ticket_hash ~ticketer ~tx_rollup;
        amount;
      }
  end

  (** [test_valid_withdraw] checks that a smart contract can deposit tickets to a
    transaction rollup. *)
  let test_valid_withdraw () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    (* The withdrawal execution operation must include proof that the
       level it specifies allows the withdrawal it executes.

       Currently, for a withdrawal execution [(level, rollup)]
       the protocol only verifies that:
       - at [level], there is a commitment for [rollup]

       It does not yet verify that the effects of the inbox at [level] actually
       enables a withdrawal.

       In this test, we simply add dummy batch and a commitment for that batch to
       to some level, which ensures that the withdrawal can be executed.

       Instead of a dummy batch, a more complete test would add:

       - A deposit operation
       - A L2->L1 operation

       This will result in a withdrawal that can be executed.
    *)

    (* 2.1 Create a ticket and its hash *)

    (* let (ticket : int Script_typed_ir.ticket) = {
     *     ticketer = account1 ;
     *     contents : contents;
     *     amount : n num
     *   } in *)

    (* 2.2 Create a withdrawal for the ticket *)
    let withdraw = Nat_ticket.withdrawal ~ticketer:account1 tx_rollup in

    (* 2.3 Add a batch message to b, a commitment for that inbox
       containing the withdrawal at index 0, and finalize that
       commitment *)
    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [withdraw])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    (* -- At this point, everything is in place for
       the user to execute the withdrawal -- *)

    (* 4. Now execute the withdrawal. The ticket should be received
       by withdraw_contract at the default entrypoint. *)
    (let entrypoint = Entrypoint.default in
     let context_hash =
       WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
     in
     let withdraw_proof = Tx_rollup_withdraw.compute_path [withdraw] 0 in
     Op.tx_rollup_withdraw
       (B b)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       withdraw_proof
       ~message_index:0
       entrypoint)
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* 5. Finally, we assert that [withdraw_contract] has
       received the ticket as expected *)
    Incremental.begin_construction b >>=? fun i ->
    let ctxt = Incremental.alpha_ctxt i in
    wrap @@ Contract.get_storage ctxt withdraw_contract
    >>=? fun (_ctxt, found_storage) ->
    Format.printf
      "found_storage %s"
      (match found_storage with
      | Some storage -> Expr.to_string storage
      | None -> "None") ;
    let expected_storage =
      Format.sprintf
        "(Some (Pair 0x%s (Pair %d %s)))"
        (Hex.show
           (Hex.of_string
              (Data_encoding.Binary.to_string_exn Contract.encoding account1)))
        Nat_ticket.contents_nat
        (Tx_rollup_l2_qty.to_string Nat_ticket.amount)
      |> Expr.from_string |> Option.some
    in
    if expected_storage = found_storage then return_unit
    else Alcotest.fail "Storage didn't match"

  (** [test_invalid_withdraw_no_commitment] checks that attempting to
   withdraw from a level with no commited inbox raises an error. *)
  let test_invalid_withdraw_no_commitment () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    Incremental.begin_construction b >>=? fun i ->
    let entrypoint = Entrypoint.default in
    let context_hash = Bytes.make 20 'c' in
    (* A dummy path *)
    let dummy_withdraw_proof =
      let ticket_hash = Ticket_hash.zero in
      let dummy_withdraw : Tx_rollup_withdraw.t =
        {
          destination = is_implicit_exn account1;
          ticket_hash;
          amount = Nat_ticket.amount;
        }
      in
      Tx_rollup_withdraw.compute_path [dummy_withdraw] 0
    in
    Op.tx_rollup_withdraw
      (I i)
      ~source:account1
      tx_rollup
      Tx_rollup_level.root
      ~context_hash
      ~message_index:0
      ~contents:(Script.lazy_expr Nat_ticket.contents)
      ~ty:(Script.lazy_expr Nat_ticket.ty)
      ~ticketer:account1
      Nat_ticket.amount
      ~destination:withdraw_contract
      dummy_withdraw_proof
      entrypoint
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:
        (check_proto_error_f @@ function
         | Tx_rollup_errors.No_finalized_commitment_for_level
             {level; window = None} ->
             Tx_rollup_level.(level = root)
         | _ -> false)
      i
      operation
    >>=? fun _ -> return_unit

  (** [test_invalid_withdraw_missing_withdraw_in_commitment] tries
     withdrawing when the commitment in question has not withdrawal
     associated.. *)
  let test_invalid_withdraw_missing_withdraw_in_commitment () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    (* 1. Create and submit a dummy batch *)
    let batch = "batch" in
    Op.tx_rollup_submit_batch (B b) account1 tx_rollup batch
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* 2.1 Create a ticket and its hash *)

    (* 2.2 Create a withdrawal for the ticket *)
    let withdraw = Nat_ticket.withdrawal ~ticketer:account1 tx_rollup in

    (* 2.3 Finally, make a commitment for the dummy batch.  mock the
       list of withdrawals to include the previously created
       [withdrawal]. Include the commitment in an operation and bake
       it. *)
    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    (* -- At this point, everything is in place for
       the user to execute the withdrawal -- *)

    (* 4. Now execute the withdrawal. The ticket should be received
       by withdraw_contract at the default entrypoint. *)
    Incremental.begin_construction b >>=? fun i ->
    (let entrypoint = Entrypoint.default in
     let context_hash =
       WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
     in
     let withdraw_path = Tx_rollup_withdraw.compute_path [withdraw] 0 in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _ -> return_unit

  (** [test_invalid_withdraw_tickets] test withdrawing with tickets
     that do not correspond to the given proof and asserts that errors
     are raised. *)
  let test_invalid_withdraw_tickets () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    (* 1. Create and submit a dummy batch *)
    let batch = "batch" in
    Op.tx_rollup_submit_batch (B b) account1 tx_rollup batch
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* 2.1 Create a ticket and its hash *)

    (* 2.2 Create a withdrawal for the ticket *)
    let withdraw = Nat_ticket.withdrawal ~ticketer:account1 tx_rollup in

    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [withdraw])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    (* -- At this point, everything is in place for
       the user to execute the withdrawal -- *)

    (* 4. Try with invalid amounts amounts *)
    let entrypoint = Entrypoint.default in
    let context_hash =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
    in
    Incremental.begin_construction b >>=? fun i ->
    List.iter_es
      (fun amount ->
        (let withdraw_path =
           Tx_rollup_withdraw.compute_path [{withdraw with amount}] 0
         in
         Op.tx_rollup_withdraw
           (I i)
           ~source:account1
           tx_rollup
           Tx_rollup_level.root
           ~context_hash
           ~message_index:0
           ~contents:(Script.lazy_expr Nat_ticket.contents)
           ~ty:(Script.lazy_expr Nat_ticket.ty)
           ~ticketer:account1
           amount
           ~destination:withdraw_contract
           withdraw_path
           entrypoint)
        >>=? fun operation ->
        Incremental.add_operation
          ~expect_failure:
            (check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
          i
          operation
        >>=? fun _i -> return_unit)
      [Tx_rollup_l2_qty.of_int64_exn 9L; Tx_rollup_l2_qty.of_int64_exn 11L]
    >>=? fun () ->
    (* 4. Try with wrong type *)
    (let withdraw_path = Tx_rollup_withdraw.compute_path [withdraw] 0 in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr @@ Expr.from_string "unit")
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _i ->
    (* 4. Try with wrong contents *)
    (let withdraw_path = Tx_rollup_withdraw.compute_path [withdraw] 0 in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr @@ Expr.from_string "2")
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _i ->
    (* 4. Try with wrong ticketer *)
    (let withdraw_path = Tx_rollup_withdraw.compute_path [withdraw] 0 in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:withdraw_contract
       Nat_ticket.amount
       ~destination:withdraw_contract
       withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _i -> return_unit

  (** [test_invalid_withdraw_invalid_proof] tries
     withdrawing with invalid proofs. *)
  let test_invalid_withdraw_invalid_proof () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    (* 1. Create and submit a dummy batch *)
    let batch = "batch" in
    Op.tx_rollup_submit_batch (B b) account1 tx_rollup batch
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* 2.1 Create a ticket and its hash *)

    (* 2.2 Create withdrawals for the ticket *)
    let withdrawal1 : Tx_rollup_withdraw.t =
      Nat_ticket.withdrawal ~ticketer:account1 tx_rollup
    in
    let withdrawal2 : Tx_rollup_withdraw.t =
      {withdrawal1 with amount = Tx_rollup_l2_qty.of_int64_exn 5L}
    in

    (* 2.3 Finally, make a commitment for the dummy batch.  mock the
       list of withdrawals to include the previously created
       [withdrawal]. Include the commitment in an operation and bake
       it. *)
    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [withdrawal1; withdrawal2])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    (* -- At this point, everything is in place for
       the user to execute the withdrawal -- *)

    (* 4. Now execute the withdrawal. The ticket should be received
       by withdraw_contract at the default entrypoint. *)
    let entrypoint = Entrypoint.default in
    let context_hash =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
    in

    Incremental.begin_construction b >>=? fun i ->
    (let invalid_withdraw_path =
       (* We're sending the parameters for withdrawal1, but we calculate
          the proof for withdrawal2 *)
       Tx_rollup_withdraw.compute_path [withdrawal1; withdrawal2] 1
     in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       invalid_withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _ ->
    (let invalid_withdraw_path =
       (* We give the proof for a list of withdrawals that does not correspond
          to the list in the commitment *)
       Tx_rollup_withdraw.compute_path [withdrawal1] 0
     in
     Op.tx_rollup_withdraw
       (I i)
       ~source:account1
       tx_rollup
       Tx_rollup_level.root
       ~context_hash
       ~message_index:0
       ~contents:(Script.lazy_expr Nat_ticket.contents)
       ~ty:(Script.lazy_expr Nat_ticket.ty)
       ~ticketer:account1
       Nat_ticket.amount
       ~destination:withdraw_contract
       invalid_withdraw_path
       entrypoint)
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _ -> return_unit

  (** [test_valid_withdraw] checks that a smart contract can deposit tickets to a
    transaction rollup. *)
  let test_invalid_withdraw_already_consumed () =
    context_init1_withdraw ()
    >>=? fun (account1, tx_rollup, withdraw_contract, b) ->
    let withdraw = Nat_ticket.withdrawal ~ticketer:account1 tx_rollup in
    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [withdraw])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    let entrypoint = Entrypoint.default in
    let context_hash =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
    in
    let withdraw_proof = Tx_rollup_withdraw.compute_path [withdraw] 0 in
    (* Execute withdraw *)
    Op.tx_rollup_withdraw
      (B b)
      ~source:account1
      tx_rollup
      Tx_rollup_level.root
      ~context_hash
      ~contents:(Script.lazy_expr Nat_ticket.contents)
      ~ty:(Script.lazy_expr Nat_ticket.ty)
      ~ticketer:account1
      Nat_ticket.amount
      ~destination:withdraw_contract
      withdraw_proof
      ~message_index:0
      entrypoint
    >>=? fun operation ->
    Block.bake ~operation b >>=? fun b ->
    (* Execute again *)
    Incremental.begin_construction b >>=? fun i ->
    Op.tx_rollup_withdraw
      (B b)
      ~source:account1
      tx_rollup
      Tx_rollup_level.root
      ~context_hash
      ~contents:(Script.lazy_expr Nat_ticket.contents)
      ~ty:(Script.lazy_expr Nat_ticket.ty)
      ~ticketer:account1
      Nat_ticket.amount
      ~destination:withdraw_contract
      withdraw_proof
      ~message_index:0
      entrypoint
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:
        (check_proto_error Apply.Tx_rollup_withdraw_already_consumed)
      i
      operation
    >>=? fun _ -> return_unit

  (** [test_invalid_withdraw_someone_elses] TODO *)
  let test_invalid_withdraw_someone_elses () =
    context_init2_withdraw ()
    >>=? fun (account1, account2, tx_rollup, withdraw_contract, b) ->
    let withdraw =
      Nat_ticket.withdrawal
        ~ticketer:account1 (* Explicit for clarity *)
        ~recipient:account1
        tx_rollup
    in
    context_finalize_batch_with_withdrawals
      ~account:account1
      ~tx_rollup
      ~withdrawals:[(0, [withdraw])]
      b
    >>=? fun (_commitment, context_hash_list, b) ->
    let entrypoint = Entrypoint.default in
    let context_hash =
      WithExceptions.Option.get ~loc:__LOC__ @@ List.nth context_hash_list 0
    in
    let withdraw_proof = Tx_rollup_withdraw.compute_path [withdraw] 0 in
    (* Execute again *)
    Incremental.begin_construction b >>=? fun i ->
    Op.tx_rollup_withdraw
      (B b)
      (* The source of the withdrawal execution is not the recipient set in [withdraw] *)
      ~source:account2
      tx_rollup
      Tx_rollup_level.root
      ~context_hash
      ~contents:(Script.lazy_expr Nat_ticket.contents)
      ~ty:(Script.lazy_expr Nat_ticket.ty)
      ~ticketer:account1
      Nat_ticket.amount
      ~destination:withdraw_contract
      withdraw_proof
      ~message_index:0
      entrypoint
    >>=? fun operation ->
    Incremental.add_operation
      ~expect_failure:(check_proto_error Tx_rollup_errors.Withdraw_invalid_path)
      i
      operation
    >>=? fun _ -> return_unit

  let tests =
    [
      Tztest.tztest "Test withdraw" `Quick test_valid_withdraw;
      Tztest.tztest
        "Test withdraw w/ missing commitment"
        `Quick
        test_invalid_withdraw_no_commitment;
      Tztest.tztest
        "Test withdraw w/ missing withdraw in commitment"
        `Quick
        test_invalid_withdraw_missing_withdraw_in_commitment;
      Tztest.tztest
        "Test withdraw w/ invalid amount"
        `Quick
        test_invalid_withdraw_tickets;
      Tztest.tztest
        "Test withdraw w/ invalid proof"
        `Quick
        test_invalid_withdraw_invalid_proof;
      Tztest.tztest
        "Test withdraw twice"
        `Quick
        test_invalid_withdraw_already_consumed;
      Tztest.tztest
        "Test withdraw someone elses's withdraw"
        `Quick
        test_invalid_withdraw_someone_elses;
    ]
end

(*

 TODO: stuff to test for withdrawals:
  - [x] test_invalid_withdraw_no_commitment: there is no commitment
  - [x] there a commitment with no withdrawals
  - [x] amount/type/contents/ticketer does not match
  - [x] erroneous proof
  - [x] trying to retrieve already retrieved withdrawal
  - [x] trying to retrieve someone else's withdrawal
  - [ ] the hash is wrong?
  - [ ] entrypoint type is wrong for destination
  - [ ] destination does not exist
  - [ ] the batch index is wrong

*)

(** [test_rejection_fail] tests that rejection successfully fails with
    a wrong rejection. *)
let test_rejection_fail () =
  context_init 2 >>=? fun (b, contracts) ->
  let contract1 =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  originate b contract1 >>=? fun (b, tx_rollup) ->
  let message = "bogus" in
  Op.tx_rollup_submit_batch (B b) contract1 tx_rollup message
  >>=? fun operation ->
  Block.bake ~operation b >>=? fun b ->
  Incremental.begin_construction b >>=? fun i ->
  let level = Tx_rollup_level.root in
  make_commitment_for_batch i level tx_rollup []
  >>=? fun (commitment, batches_result) ->
  Op.tx_rollup_commit (I i) contract1 tx_rollup commitment >>=? fun op ->
  Incremental.add_operation i op >>=? fun i ->
  (* Here, we create an invalid proof: we have a single message which
     is invalid, and thus the expected before_root should be equal
     to the after_root, which is equal to the empty tree.  And indeed,
     that is precisely what the commitment says will happen. So
     the rejection is invalid. TODO/TORU: create a batch with messages,
     and check valid and invalid rejections of that. *)
  let proof : Tx_rollup_rejection_proof.t =
    {
      version = 0;
      before = `Value empty_context_hash;
      after = `Value empty_context_hash;
      state = Seq.empty;
    }
  in
  let (message, _size) = Tx_rollup_message.make_batch message in
  let result =
    match List.nth_opt batches_result 0 with
    | None -> assert false
    | Some result -> result
  in
  Op.tx_rollup_reject
    (I i)
    contract1
    tx_rollup
    level
    message
    ~message_position:0
    ~proof
    ~before_root:empty_context_hash
    ~before_withdraw:(Tx_rollup_withdraw.hash_list [])
    ~after_result:(Tx_rollup_commitment_message_result_hash.of_bytes_exn result)
  >>=? fun op ->
  Incremental.add_operation
    i
    op
    ~expect_failure:(check_proto_error Tx_rollup_errors.Invalid_proof)
  >>=? fun i ->
  ignore i ;

  return ()

let tests =
  [
    Tztest.tztest
      "check feature flag is disabled"
      `Quick
      test_disable_feature_flag;
    Tztest.tztest "check tx rollup origination and burn" `Quick test_origination;
    Tztest.tztest
      "check two originated tx rollup in one operation have different address"
      `Quick
      test_two_originations;
    Tztest.tztest
      "check the function that updates the burn per byte rate of a transaction \
       rollup"
      `Quick
      test_burn_per_byte_update;
    Tztest.tztest "add one batch to a rollup" `Quick test_add_batch;
    Tztest.tztest "add two batches to a rollup" `Quick test_add_two_batches;
    Tztest.tztest
      "add one batch and limit the burn"
      `Quick
      test_add_batch_with_limit;
    Tztest.tztest
      "Try to add a batch larger than the limit"
      `Quick
      test_batch_too_big;
    Tztest.tztest
      "Try to add several batches to reach the inbox size limit"
      `Quick
      test_inbox_size_too_big;
    Tztest.tztest
      "Try to add several batches to reach the inbox count limit"
      `Quick
      test_inbox_count_too_big;
    Tztest.tztest "Test deposit with valid contract" `Quick test_valid_deposit;
    Tztest.tztest
      "Test deposit with invalid parameter"
      `Quick
      test_invalid_deposit_not_ticket;
    Tztest.tztest
      "Test valid deposit to inexistant rollup"
      `Quick
      test_valid_deposit_inexistant_rollup;
    Tztest.tztest "Test invalid entrypoint" `Quick test_invalid_entrypoint;
    Tztest.tztest
      "Test valid deposit to invalid L2 address"
      `Quick
      test_invalid_l2_address;
    Tztest.tztest
      "Test valid deposit with non-zero amount"
      `Quick
      test_valid_deposit_invalid_amount;
    Tztest.tztest "Test finalization" `Quick test_finalization;
    Tztest.tztest "Smoke test commitment" `Quick test_commitment_duplication;
    Tztest.tztest
      "Test commitment predecessor edge cases"
      `Quick
      test_commitment_predecessor;
    Tztest.tztest "Test full inbox" `Quick test_full_inbox;
    Tztest.tztest
      "Test too many finalized commitments"
      `Quick
      test_too_many_commitments;
    Tztest.tztest "Test bond finalization" `Quick test_bond_finalization;
    Tztest.tztest "Test rejection" `Quick test_rejection_fail;
  ]
  @ Withdraw.tests
