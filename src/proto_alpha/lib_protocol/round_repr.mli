(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
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

(** A round represents an iteration of the single-shot consensus algorithm.

   Rounds can be seen as an infinite, 0-indexed, list of durations. The
   durations are generated by an arithmetic progression depending on
   {!val:Constants_repr.minimal_block_delay} (its initial value, a.k.a the one for
   round 0) and {!val:Constants_repr.delay_increment_per_round} (its common
   difference) .

   Round identifiers are non-negative 32 bit integers. This interface ensures
   that no negative round can be created. *)

type round

type t = round

(** Round zero  *)
val zero : t

(** Successor of the given round.
    Return an error if applied to the maximal value of rounds *)
val succ : t -> t tzresult

(** Predecessor of the given round.
    Returns an error if applied to [zero], as negative round are
    prohibited. *)
val pred : t -> t tzresult

(** Building a round from an int32.
    Returns an error if applied to a negative number. *)
val of_int32 : int32 -> t tzresult

val to_int32 : t -> int32

(** Building a round from an int.
    Returns an error if applied to a negative number or a number
    greater than Int32.max_int. *)
val of_int : int -> t tzresult

(** Building an int from a round.
    Returns an error if the value does not fit in max_int. (current
    32bit encodings always fit in int on 64bit architecture though). *)
val to_int : t -> int tzresult

(** Returns the slot corresponding to the given round [r], that is [r
   mod committee_size]. *)
val to_slot : t -> committee_size:int -> Slot_repr.t tzresult

(** Round encoding.
    Be aware that decoding a negative 32 bit integer would lead to an
    exception. *)
val encoding : t Data_encoding.t

val pp : Format.formatter -> t -> unit

include Compare.S with type t := t

module Map : Map.S with type key = t

(** {2 Round duration representation} *)

module Durations : sig
  (** [round_durations] represents the duration of rounds in seconds *)
  type t

  val pp : Format.formatter -> t -> unit

  (** {3 Creation functions} *)

  (** [create ~first_round_duration ~delay_increment_per_round] creates a valid
      duration value

      @param first_round_duration minimal amount of time that a round should last
      @param delay_increment_per_round amount of time added in from one round
                                       duration to the duration of its next round
      @raises Invalid_argument if
        - first_round_duration <= 1; or
        - delay_increment_per_round is < 0
   *)
  val create :
    first_round_duration:Period_repr.t ->
    delay_increment_per_round:Period_repr.t ->
    t tzresult

  (** [create_opt ~first_round_duration ~delay_increment_per_round] returns a valid duration value
      [Some d] when [create ~first_round_duration ~delay_increment_per_round]
      does not fail. It returns [None] otherwise. *)
  val create_opt :
    first_round_duration:Period_repr.t ->
    delay_increment_per_round:Period_repr.t ->
    t option

  (** {b Warning} May trigger an exception when the expected invariant
      does not hold. *)
  val encoding : t Data_encoding.encoding

  (** {3 Accessors}*)

  (** [round_duration round_durations ~round] returns the duration of round
      [~round]. This duration follows the arithmetic progression

      duration(round_n) = [first_round_duration] + n * [delay_increment_per_round]

   *)
  val round_duration : t -> round -> Period_repr.t
end

(** [level_offset_of_round round_durations ~round:r] represents the offset of the
    starting time of round [r] with respect to the start of the level.
    round = 0      1     2    3                            r

          |-----|-----|-----|-----|-----|--- ... ... --|------|-------
                                                       |
          <------------------------------------------->
                              level_offset
*)
val level_offset_of_round : Durations.t -> round:t -> Period_repr.t tzresult

(** [timestamp_of_round round_durations ~predecessor_timestamp:pred_ts
     ~predecessor_round:pred_round ~round] returns the
    starting time of round [round] given that the timestamp and the round of
    the block at the previous level is [pred_ts] and [pred_round],
    respectively.

    pred_round = 0            pred_round

              |-----|.. ... --|--------|-- ... --|-------
                              |        |
                              |        |
                           pred_ts     |
                                       |
                                start_of_cur_level
                                       |
                                       |
                                       |-----|------|-- ... --|-------|-
    cur_round =                           0      1            | round
                                                              |
                                                            res_ts

    Precisely, the resulting timestamp is:
      [pred_ts + round_duration(pred_round) + level_offset_of_round(round)].
*)
val timestamp_of_round :
  Durations.t ->
  predecessor_timestamp:Time_repr.t ->
  predecessor_round:t ->
  round:t ->
  Time_repr.t tzresult

(** [timestamp_of_another_round_same_level
        round_durations
        ~current_timestamp
        ~current_round
        ~considered_round]
       returns the starting time of round [considered_round].

       start of current
            level         current ts      result
              |               |             |
              |               |             |
              |-----|----...--|-- ... ------|-
              |     |         |             |
  cur_round = 0     1      current      considered
                            round         round

    It also works when [considered_round] is lower than [current_round].

  Precisely, the resulting timestamp is:
    [current_timestamp - level_offset_of_round(current_round)
                       + level_offset_of_round(considered_round)].
*)
val timestamp_of_another_round_same_level :
  Durations.t ->
  current_timestamp:Time_repr.t ->
  current_round:t ->
  considered_round:t ->
  Time_repr.t tzresult

(** [round_of_timestamp round_durations ~predecessor_timestamp ~predecessor_round
     ~timestamp:ts] returns the round to which the timestamp [ts] belongs to,
    given that the timestamp and the round of the block at the previous level is
    [pred_ts] and [pred_round], respectively.

    Precisely, the resulting round is:
      [round_and_offset round_durations ~level_offset:diff] where
    [diff = ts - (predecessor_timestamp + round_duration(predecessor_round)].

    Returns an error when the timestamp is before the level start.*)
val round_of_timestamp :
  Durations.t ->
  predecessor_timestamp:Time_repr.t ->
  predecessor_round:t ->
  timestamp:Time_repr.t ->
  t tzresult

module Internals_for_test : sig
  type round_and_offset_raw = {round : round; offset : Period_repr.t}

  (** [round_and_offset round_durations ~level_offset], where [level_offset]
    represents a time offset with respect to the start of the first round,
    returns a tuple [(r, round_offset)] where the round [r] is such that
    [level_offset_of_round(r) <= level_offset < level_offset_of_round(r+1)] and
    [round_offset := level_offset - level_offset_of_round(r)]].

    round = 0      1     2    3                            r

          |-----|-----|-----|-----|-----|--- ... ... --|--------|-- ... --|-------
                                                       |
                                                 round_delay(r)
                                                              |
                                                              |
                                                        <----->
                                                      round_offset
          <--------------------------------------------------->
                              level_offset
*)
  val round_and_offset :
    Durations.t -> level_offset:Period_repr.t -> round_and_offset_raw tzresult
end
