(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Trili Tech, <contact@trili.tech>                       *)
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

module S = Saturation_repr

module S_syntax = struct
  let ( + ) = S.add

  let ( * ) = S.mul
end

module Constants = struct
  (* TODO: https://gitlab.com/tezos/tezos/-/issues/2648
     Fill in real benchmarked values.
     Need to create benchmark and fill in values.
  *)
  let cost_add_message_base = S.safe_int 430

  let cost_add_message_per_byte = S.safe_int 15
end

(* We assume that the gas cost of adding a message `m` to the
   inbox is linear in the length of the message `length(m)`, that is
   [cost_add_message m] = `cost_add_message_base +
   cost_add_message_per_byte * length(m)`.
*)
let cost_add_message m =
  let open S_syntax in
  let l = String.length m in
  Constants.cost_add_message_base
  + (Constants.cost_add_message_per_byte * S.safe_int l)

let cost_add_messages messages =
  let open S_syntax in
  let messages_costs = List.map cost_add_message messages in
  List.fold_left ( + ) S.zero messages_costs
