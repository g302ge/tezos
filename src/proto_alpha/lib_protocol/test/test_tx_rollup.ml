(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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
    Invocation:   dune exec src/proto_alpha/lib_protocol/test/main.exe -- test "^tx rollup$"
    Subject:      Test rollup
*)

open Protocol
open Alpha_context
open Test_tez

let tez_testable = Alcotest.testable Tez.pp Tez.( = )

(** [test_disable_feature_flag] try to originate a tx rollup with the feature
    flag is deactivated and check it fails *)
let test_disable_feature_flag () =
  Context.init 1 >>=? fun (b, contracts) ->
  let contract =
    WithExceptions.Option.get ~loc:__LOC__ @@ List.nth contracts 0
  in
  Incremental.begin_construction b >>=? fun i ->
  Op.tx_rollup_origination (I i) contract >>=? fun (op, _tx_rollup) ->
  let expect_failure = function
    | Environment.Ecoproto_error (Apply.Tx_rollup_disabled as e) :: _ ->
        Assert.test_error_encodings e ;
        return_unit
    | _ -> failwith "It should not be possible to send a rollup_operation "
  in
  Incremental.add_operation ~expect_failure i op >>= fun _i -> return_unit

(** [test_origination] originate a tx rollup and check that it burns the
    correct amount of the origination source contract. *)
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
  Context.Tx_rollup.state (I i) tx_rollup >>=? fun _ ->
  cost_per_byte *? Int64.of_int tx_rollup_origination_size
  >>?= fun tx_rollup_origination_burn ->
  Assert.balance_was_debited
    ~loc:__LOC__
    (I i)
    contract
    balance
    tx_rollup_origination_burn

(** [test_two_origination] originate two tx rollups in the same operation and
    check that each has a different address. *)
let test_two_origination () =
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
    "Origination of two tx rollups in one operation have different addresses"
    Tx_rollup.pp
    txo1
    txo2
  >>=? fun () ->
  Context.Tx_rollup.state (I i) txo1 >>=? fun _ ->
  Context.Tx_rollup.state (I i) txo2 >>=? fun _ -> return_unit

(** Check that the cost per byte per inbox rate is updated correctly *)
let test_cost_per_byte_update () =
  let cost_per_byte = Tez.of_mutez_exn 250L in
  let test ~tx_rollup_cost_per_byte ~final_size ~hard_limit ~result ~message =
    let result = Tez.of_mutez_exn result in
    let tx_rollup_cost_per_byte = Tez.of_mutez_exn tx_rollup_cost_per_byte in
    let new_cost_per_byte =
      Alpha_context.Tx_rollup.Internal_for_tests.update_cost_per_byte
        ~cost_per_byte
        ~tx_rollup_cost_per_byte
        ~final_size
        ~hard_limit
    in
    Alcotest.check tez_testable message result new_cost_per_byte
  in

  test
    ~tx_rollup_cost_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_100
    ~result:1_000L
    ~message:"Cost per byte should remain constant" ;
  test
    ~tx_rollup_cost_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_000
    ~result:1_051L
    ~message:"Cost per byte should increase" ;
  test
    ~tx_rollup_cost_per_byte:1_000L
    ~final_size:1_000
    ~hard_limit:1_500
    ~result:951L
    ~message:"Cost per byte should decrease" ;

  test
    ~tx_rollup_cost_per_byte:(cost_per_byte |> Tez.to_mutez)
    ~final_size:1_000
    ~hard_limit:1_500
    ~result:(cost_per_byte |> Tez.to_mutez)
    ~message:"Cost per byte never decreased under the [cost_per_byte] constant" ;

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
      test_two_origination;
    Tztest.tztest
      "check the function that updates the cost per byte rate per inbox"
      `Quick
      test_cost_per_byte_update;
  ]
