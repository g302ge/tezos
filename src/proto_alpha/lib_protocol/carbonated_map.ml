(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021-2022 Trili Tech, <contact@trili.tech>                  *)
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

open Alpha_context

module type S =
  Raw_carbonated_map.S
    with type context := Alpha_context.t
     and type cost := Alpha_context.Gas.cost

module type COMPARABLE = sig
  include Compare.COMPARABLE

  val compare_cost : t -> Gas.cost
end

module Make_Gas_Cost (C : COMPARABLE) :
  Raw_carbonated_map.GAS_COSTS
    with type t = C.t
     and type context = Alpha_context.t = struct
  type t = C.t

  type cost = Gas.cost

  type context = Alpha_context.t

  (** [compare_cost k] returns the cost of comparing the given key [k] with
      another value of the same type. *)
  let compare_cost = C.compare_cost

  let find_cost = Carbonated_map_costs.find_cost

  let update_cost = Carbonated_map_costs.update_cost

  let fold_cost = Carbonated_map_costs.fold_cost

  let consume_gas = Gas.consume
end

module Make (C : COMPARABLE) = Raw_carbonated_map.Make (C) (Make_Gas_Cost (C))
