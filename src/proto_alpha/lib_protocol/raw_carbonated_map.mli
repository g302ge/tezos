(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Trili Tech, <contact@trili.tech>                       *)
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

(** An in-memory data-structure for a key-value map where all operations
    account for gas costs.
 *)
module type S = sig
  type 'a t

  (** The type of keys in the map. *)
  type key

  (** The type used for the gas cost *)
  type cost

  (** The type used for the context *)
  type context

  (** [empty] an empty map. *)
  val empty : 'a t

  (** [singleton k v] returns a map with a single key [k] and value [v] pair. *)
  val singleton : key -> 'a -> 'a t

  (** [size m] returns the number of elements of the map [m] in constant time. *)
  val size : 'a t -> int

  (** [find ctxt k m] looks up the value with key [k] in the given map [m] and
      also consumes the gas associated with the lookup. The complexity is
      logarithmic in the size of the map. *)
  val find : context -> key -> 'a t -> ('a option * context) tzresult

  (** [update ctxt k f map] updates or adds the value of the key [k] using [f].
      The function accounts for the gas cost for finding the element. The updating
      function [f] should also account for its own gas cost. The complexity is
      logarithmic in the size of the map. *)
  val update :
    context ->
    key ->
    (context -> 'a option -> ('a option * context) tzresult) ->
    'a t ->
    ('a t * context) tzresult

  (** [to_list m] transforms a map [m] into a list. It also accounts for the
      gas cost for traversing the elements. The complexity is linear in the size
      of the map. *)
  val to_list : context -> 'a t -> ((key * 'a) list * context) tzresult

  (** [of_list ctxt ~merge_overlaps m] creates a map from a list of key-value
      pairs. In case there are overlapping keys, their values are combined
      using the [merge_overlap] function. The function accounts for gas for
      traversing the elements. [merge_overlap] should account for its own gas
      cost. The complexity is [n * log n] in the size of the list.
      *)
  val of_list :
    context ->
    merge_overlap:(context -> 'a -> 'a -> ('a * context) tzresult) ->
    (key * 'a) list ->
    ('a t * context) tzresult

  (** [merge ctxt ~merge_overlap m1 m2] merges the maps [m1] and [m2]. In case
      there are overlapping keys, their values are combined using the
      [merge_overlap] function. Gas costs for traversing all elements from both
      maps are accounted for. [merge_overlap] should account for its own gas
      cost. The complexity is [n * log n], where [n]
      is [size m1 + size m2]. *)
  val merge :
    context ->
    merge_overlap:(context -> 'a -> 'a -> ('a * context) tzresult) ->
    'a t ->
    'a t ->
    ('a t * context) tzresult

  (** [map ctxt f m] maps over all key-value pairs in the map [m] using the
      function [f]. It accounts for gas costs associated with traversing the
      elements. The mapping function [f] should also account for its own gas
      cost. The complexity is linear in the size of the map [m]. *)
  val map :
    context ->
    (context -> key -> 'a -> ('b * context) tzresult) ->
    'a t ->
    ('b t * context) tzresult

  (** [fold ctxt f z m] folds over the key-value pairs of the given map [m],
      accumulating values using [f], with [z] as the initial state. The function
      [f] must account for its own gas cost. The complexity is linear in the
      size of the map [m]. *)
  val fold :
    context ->
    (context -> 'state -> key -> 'value -> ('state * context) tzresult) ->
    'state ->
    'value t ->
    ('state * context) tzresult
end

(** FILL ME. *)
module type GAS_COSTS = sig
  type t

  type cost

  type context

  (** [compare_cost k] returns the cost of comparing the given key [k] with
      another value of the same type. *)
  val compare_cost : t -> cost

  val find_cost : compare_key_cost:cost -> size:int -> cost

  val update_cost : compare_key_cost:cost -> size:int -> cost

  val fold_cost : size:int -> cost

  val consume_gas : context -> cost -> context tzresult
end

(** A functor for building gas metered maps. *)
module Make (O : Compare.COMPARABLE) (G : GAS_COSTS with type t = O.t) :
  S with type key := O.t and type cost := G.cost and type context := G.context
