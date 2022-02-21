(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
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
    Component:  Protocol Liquidity_baking_repr module
    Invocation: dune exec src/proto_alpha/lib_protocol/test/unit/main.exe \
      -- test "^\[Unit\] liquidity baking$"
    Subject:    Tests for the Liquidity_baking_repr module
*)

open Protocol

let ema_of_int32 ema =
  Liquidity_baking_repr.Escape_EMA.of_int32 ema >|= Environment.wrap_tzresult

let ema_to_int32 = Liquidity_baking_repr.Escape_EMA.to_int32

let compute_new_ema ~escape_vote ema =
  Liquidity_baking_repr.compute_new_ema ~escape_vote ema |> ema_to_int32

(* Folds compute_new_ema on a list of votes *)
let compute_new_ema_n escape_votes initial_ema =
  List.fold_left
    (fun ema escape_vote ->
      Liquidity_baking_repr.compute_new_ema ~escape_vote ema)
    initial_ema
    escape_votes
  |> ema_to_int32

let ema_range =
  [
    0l;
    1l;
    10l;
    100l;
    1000l;
    10_000l;
    100_000l;
    1_000_000l;
    10_000_000l;
    100_000_000l;
    200_000_000l;
    300_000_000l;
    400_000_000l;
    500_000_000l;
    600_000_000l;
    760_000_000l;
    800_000_000l;
    900_000_000l;
    1_000_000_000l;
    1_100_000_000l;
    1_200_000_000l;
    1_300_000_000l;
    1_400_000_000l;
    1_500_000_000l;
    1_600_000_000l;
    1_700_000_000l;
    1_800_000_000l;
    1_900_000_000l;
    1_990_000_000l;
    1_999_000_000l;
    1_999_900_000l;
    1_999_990_000l;
    1_999_999_000l;
    1_999_999_900l;
    1_999_999_990l;
    1_999_999_999l;
    2_000_000_000l;
  ]

(* Test that new_ema = old_ema when voting Pass. *)
let test_ema_pass () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      Assert.equal_int32
        ~loc:__LOC__
        (compute_new_ema ~escape_vote:LB_pass ema)
        old_ema)
    ema_range

(* Test that new_ema is still between 0 and 2,000,000,000 after an Off vote. *)
let test_ema_in_bound_off () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      let new_ema = compute_new_ema ~toggle_vote:LB_off ema in
      Assert.leq_int32 ~loc:__LOC__ 0l new_ema >>=? fun () ->
      Assert.leq_int32 ~loc:__LOC__ new_ema 2_000_000_000l)
    ema_range

(* Test that new_ema > old_ema when voting Off, except if old_ema is
   already very close to the upper bound. *)
let test_ema_increases_off () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      Assert.lt_int32
        ~loc:__LOC__
        old_ema
        (compute_new_ema ~escape_vote:LB_off ema))
    (List.filter (fun ema -> Compare.Int32.(ema < 1_999_999_000l)) ema_range)

(* Test that the increase in EMA caused by an Off vote is bounded by 1,000,000 *)
let test_ema_increases_off_bound () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      Assert.leq_int32
        ~loc:__LOC__
        (Int32.sub (compute_new_ema ~escape_vote:LB_off ema) old_ema)
        1_000_000l)
    ema_range

(* Test that new_ema is still between 0 and 2,000,000,000 after an Off vote. *)
let test_ema_in_bound_on () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      let new_ema = compute_new_ema ~toggle_vote:LB_on ema in
      Assert.leq_int32 ~loc:__LOC__ 0l new_ema >>=? fun () ->
      Assert.leq_int32 ~loc:__LOC__ new_ema 2_000_000_000l)
    ema_range

(* Test that new_ema < old_ema when voting On, except if old_ema is
   already very close to the lower bound. *)
let test_ema_decreases_on () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      Assert.lt_int32
        ~loc:__LOC__
        (compute_new_ema ~escape_vote:LB_on ema)
        old_ema)
    (List.filter (fun ema -> Compare.Int32.(ema > 1000l)) ema_range)

(* Test that the decrease in EMA caused by an On vote is bounded by 1,000,000 *)
let test_ema_decreases_on_bound () =
  List.iter_es
    (fun old_ema ->
      ema_of_int32 old_ema >>=? fun ema ->
      Assert.leq_int32
        ~loc:__LOC__
        (Int32.sub (compute_new_ema ~escape_vote:LB_on ema) old_ema)
        1_000_000l)
    ema_range

(* Test that 1385 Off votes are needed to reach the threshold from 0. *)
let test_ema_many_off () =
  let open Liquidity_baking_repr in
  ema_of_int32 0l >>=? fun initial_ema ->
  Assert.leq_int32
    ~loc:__LOC__
    (compute_new_ema_n (Stdlib.List.init 1385 (fun _ -> LB_off)) initial_ema)
    1_000_000_000l
  >>=? fun () ->
  Assert.leq_int32
    ~loc:__LOC__
    1_000_000_000l
    (compute_new_ema_n (Stdlib.List.init 1386 (fun _ -> LB_off)) initial_ema)

(* Test that 1385 On votes are needed to reach the threshold from the max value of the EMA (2,000,000,000). *)
let test_ema_many_on () =
  let open Liquidity_baking_repr in
  ema_of_int32 2_000_000_000l >>=? fun initial_ema ->
  Assert.leq_int32
    ~loc:__LOC__
    1_000_000_000l
    (compute_new_ema_n (Stdlib.List.init 1385 (fun _ -> LB_on)) initial_ema)
  >>=? fun () ->
  Assert.leq_int32
    ~loc:__LOC__
    (compute_new_ema_n (Stdlib.List.init 1386 (fun _ -> LB_on)) initial_ema)
    1_000_000_000l

(* Test that the EMA update function is symmetric:
   from two dual values of the EMA (that is, two values x and y such that
   x + y = 2,000,000,000), voting On on the first one decreases it by as
   much than voting Off on the second one increases it.
*)
let test_ema_symmetry () =
  List.iter_es
    (fun ema ->
      let opposite_ema = Int32.(sub 2_000_000_000l ema) in
      ema_of_int32 ema >>=? fun ema ->
      ema_of_int32 opposite_ema >>=? fun opposite_ema ->
      let new_ema = compute_new_ema ~escape_vote:LB_on ema in
      let new_opposite_ema = compute_new_ema ~escape_vote:LB_off opposite_ema in
      Assert.equal_int32
        ~loc:__LOC__
        Int32.(add new_ema new_opposite_ema)
        2_000_000_000l)
    ema_range

let tests =
  [
    Tztest.tztest
      "Test EMA does not change when vote is Pass"
      `Quick
      test_ema_pass;
    Tztest.tztest
      "Test EMA remains in bounds when vote is Off"
      `Quick
      test_ema_in_bound_off;
    Tztest.tztest
      "Test EMA increases when vote is Off"
      `Quick
      test_ema_increases_off;
    Tztest.tztest
      "Test EMA does not increase too much when vote is Off"
      `Quick
      test_ema_increases_off_bound;
    Tztest.tztest
      "Test EMA remains in bounds when vote is On"
      `Quick
      test_ema_in_bound_on;
    Tztest.tztest
      "Test EMA decreases when vote is On"
      `Quick
      test_ema_decreases_on;
    Tztest.tztest
      "Test EMA does not decrease too much when vote is On"
      `Quick
      test_ema_decreases_on_bound;
    Tztest.tztest
      "Test EMA goes from 0 to one billion in 1386 Off votes"
      `Quick
      test_ema_many_off;
    Tztest.tztest
      "Test EMA goes from two billions to one billion in 1386 On votes"
      `Quick
      test_ema_many_on;
    Tztest.tztest
      "Test that voting On and Off have symmetric effects on the EMA"
      `Quick
      test_ema_symmetry;
  ]
