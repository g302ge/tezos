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

type alert_config = {
  default_slack_webhook_url : Uri.t;
  team_slack_webhook_urls : Uri.t String_map.t;
  max_total : int;
  max_by_test : int;
  gitlab_project_url : Uri.t option;
  timeout : float;
}

type config = {
  alerts : alert_config option;
  influxdb : InfluxDB.config option;
  grafana : Grafana.config option;
}

let default default = Option.value ~default

let as_alert_config json =
  let slack_webhook_urls = JSON.(json |-> "slack_webhook_urls") in
  let team_slack_webhook_urls =
    JSON.as_object slack_webhook_urls
    |> List.filter_map (fun (name, url) ->
           if name = "default" then None
           else Some (name, JSON.(url |> as_string |> Uri.of_string)))
    |> List.fold_left
         (fun acc (k, v) -> String_map.add k v acc)
         String_map.empty
  in
  {
    default_slack_webhook_url =
      JSON.(slack_webhook_urls |-> "default" |> as_string |> Uri.of_string);
    team_slack_webhook_urls;
    max_total = JSON.(json |-> "max_total" |> as_int_opt |> default 100);
    max_by_test = JSON.(json |-> "max_by_test" |> as_int_opt |> default 2);
    gitlab_project_url =
      JSON.(
        json |-> "gitlab_project_url" |> as_string_opt
        |> Option.map Uri.of_string);
    timeout =
      JSON.(json |-> "timeout" |> as_float_opt |> Option.value ~default:20.);
  }

let read_config_file filename =
  let json = JSON.parse_file filename in
  {
    alerts = JSON.(json |-> "alerts" |> as_opt |> Option.map as_alert_config);
    influxdb =
      JSON.(json |-> "influxdb" |> as_opt |> Option.map InfluxDB.config_of_json);
    grafana =
      JSON.(json |-> "grafana" |> as_opt |> Option.map Grafana.config_of_json);
  }

let config =
  match
    match Sys.getenv_opt "TEZT_CONFIG" with
    | Some "" | None -> (
        if Sys.file_exists "tezt_config.json" then Some "tezt_config.json"
        else
          match Sys.getenv_opt "HOME" with
          | Some home ->
              let filename = home // ".tezt_config.json" in
              if Sys.file_exists filename then Some filename else None
          | None -> None)
    | Some _ as x -> x
  with
  | None ->
      Log.warn "No configuration file found, using default configuration." ;
      {alerts = None; influxdb = None; grafana = None}
  | Some filename -> (
      Log.info "Using configuration file: %s" filename ;
      try read_config_file filename
      with JSON.Error error ->
        Log.error
          "Failed to read configuration file: %s"
          (JSON.show_error error) ;
        exit 1)

let () =
  if config.alerts = None then
    Log.warn "Alerts are not configured and will thus not be sent." ;
  if config.influxdb = None then
    Log.warn
      "InfluxDB is not configured: data points will not be sent and previous \
       data points will not be read. Also, Grafana dashboards will not be \
       updated." ;
  if config.grafana = None then
    Log.warn
      "Grafana is not configured: Grafana dashboards will not be updated."

type timeout = Seconds of int | Minutes of int | Hours of int | Days of int

let with_timeout timeout promise () =
  let timeout =
    match timeout with
    | Seconds x -> x
    | Minutes x -> x * 60
    | Hours x -> x * 60 * 60
    | Days x -> x * 60 * 60 * 24
  in
  Lwt.pick
    [
      promise;
      (let* () = Lwt_unix.sleep (float timeout) in
       Test.fail "test did not finish before its timeout");
    ]

(* [data_points] is a map from measurement to lists.
   The order of those lists is unspecified. *)
type current_test = {
  title : string;
  filename : string;
  team : string option;
  mutable data_points : InfluxDB.data_point list String_map.t;
  mutable alert_count : int;
}

(* Using a global variable will make it hard to refactor to run
   multiple tests concurrently if we want to. But, running multiple
   tests would affect time measurements so it is not advisable anyway. *)
let current_test = ref None

let total_alert_count = ref 0

let http ~timeout method_ ?headers ?body url =
  let http_call =
    let headers = Option.map Cohttp.Header.of_list headers in
    let body = Option.map (fun s -> `String s) body in
    Cohttp_lwt_unix.Client.call ?headers ?body method_ url
  in
  let timeout =
    let* () = Lwt_unix.sleep timeout in
    failwith "timeout"
  in
  Lwt.pick [http_call; timeout]

let http_post_json url body =
  http
    `POST
    ~headers:[("Content-Type", "application/json")]
    ~body:(JSON.encode_u body)
    url

let with_buffer size f =
  let buffer = Buffer.create size in
  f buffer ;
  Buffer.contents buffer

module Slack = struct
  let encode_entities buffer s =
    for i = 0 to String.length s - 1 do
      match s.[i] with
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer ">gt;"
      | c -> Buffer.add_char buffer c
    done

  type message_item =
    | Text of string
    | Newline
    | Link of {url : Uri.t; text : string}

  type message = message_item list

  let encode_message_item buffer = function
    | Text s -> encode_entities buffer s
    | Newline -> Buffer.add_char buffer '\n'
    | Link {url; text} ->
        Buffer.add_char buffer '<' ;
        Buffer.add_string buffer (Uri.to_string url) ;
        Buffer.add_char buffer '|' ;
        encode_entities buffer text ;
        Buffer.add_char buffer '>'

  let send_message ~timeout webhook_url message =
    let message =
      with_buffer 256 @@ fun buffer ->
      List.iter (encode_message_item buffer) message
    in
    let body = `O [("text", `String message)] in
    let send () =
      let* (response, body) = http_post_json ~timeout webhook_url body in
      match response.status with
      | #Cohttp.Code.success_status -> Cohttp_lwt.Body.drain_body body
      | status ->
          let* body = Cohttp_lwt.Body.to_string body in
          Log.debug "Response body from Slack: %s" body ;
          Log.warn
            "Failed to send message: Slack responded with %s"
            (Cohttp.Code.string_of_status status) ;
          unit
    in
    Lwt.catch send @@ fun exn ->
    Log.warn "Failed to send message to Slack: %s" (Printexc.to_string exn) ;
    unit
end

let alert_s ~log message =
  if log then Log.error "Alert: %s" message ;
  match config.alerts with
  | None -> ()
  | Some alert_cfg ->
      let may_send =
        !total_alert_count < alert_cfg.max_total
        &&
        match !current_test with
        | None -> true
        | Some {alert_count; _} -> alert_count < alert_cfg.max_by_test
      in
      if may_send then
        let slack_webhook_url =
          match !current_test with
          | Some {team = Some team; _} -> (
              match
                String_map.find_opt team alert_cfg.team_slack_webhook_urls
              with
              | None ->
                  Log.warn
                    "No Slack webhook configured for team %S, will use the \
                     default."
                    team ;
                  alert_cfg.default_slack_webhook_url
              | Some url -> url)
          | _ -> alert_cfg.default_slack_webhook_url
        in
        let message : Slack.message =
          match !current_test with
          | None -> [Text "Alert: "; Text message]
          | Some {title; filename; _} -> (
              let text =
                Slack.Text (sf "Alert from test %S: %s" title message)
              in
              match alert_cfg.gitlab_project_url with
              | None -> [text]
              | Some gitlab_project_url ->
                  let new_issue_url =
                    let issue_title = sf "Fix test: %s" title in
                    let issue_description =
                      sf "Test: %s\nFile: %s\nAlert: %s" title filename message
                    in
                    let url =
                      let path = Uri.path gitlab_project_url in
                      Uri.with_path gitlab_project_url (path ^ "/-/issues/new")
                    in
                    Uri.add_query_params'
                      url
                      [
                        ("issue[title]", issue_title);
                        ("issue[description]", issue_description);
                      ]
                  in
                  [
                    text;
                    Newline;
                    Link {url = new_issue_url; text = "create issue"};
                  ])
        in
        (* Using [Background.register] is not just about returning type [unit]
           instead of a promise, it also prevents the timeout of the test from
           canceling the alert. *)
        Background.register
        @@ Slack.send_message
             ~timeout:alert_cfg.timeout
             slack_webhook_url
             message

let alert x = Printf.ksprintf (alert_s ~log:true) x

let alert_exn exn x =
  Printf.ksprintf
    (fun s ->
      Log.error "Alert: %s: %s" s (Printexc.to_string exn) ;
      alert_s ~log:false s)
    x

let add_data_point data_point =
  match !current_test with
  | None ->
      invalid_arg
        "Long_test.add_data_point: not running a test registered with Long_test"
  | Some test ->
      (* Title has already been checked for newline characters in [register]. *)
      let data_point = InfluxDB.add_tag "test" test.title data_point in
      Log.debug "Data point: %s" (InfluxDB.show_data_point data_point) ;
      let previous_data_points =
        String_map.find_opt data_point.measurement test.data_points
        |> Option.value ~default:[]
      in
      test.data_points <-
        String_map.add
          data_point.measurement
          (data_point :: previous_data_points)
          test.data_points

let send_data_points () =
  match (!current_test, config.influxdb) with
  | (None, _) | (_, None) -> unit
  | (Some test, Some config) ->
      let write () =
        let data_points =
          test.data_points |> String_map.bindings |> List.map snd
          |> List.flatten
        in
        test.data_points <- String_map.empty ;
        match data_points with
        | [] -> unit
        | _ ->
            let* () = InfluxDB.write config data_points in
            Log.debug
              "Successfully sent %d data points."
              (List.length data_points) ;
            unit
      in
      Lwt.catch write (fun exn ->
          alert_exn exn "failed to send data points to InfluxDB" ;
          unit)

let unsafe_query select extract_data =
  match config.influxdb with
  | None ->
      Log.debug
        "InfluxDB is not configured, will not perform query: %s"
        (InfluxDB.show_select select) ;
      none
  | Some config ->
      let query () =
        let* result = InfluxDB.query config select in
        some (extract_data result)
      in
      Lwt.catch query (fun exn ->
          Log.debug "Query: %s" (InfluxDB.show_select select) ;
          alert_exn exn "failed to perform InfluxDB query" ;
          none)

let log_unsafe_query select =
  let* result = unsafe_query select Fun.id in
  Option.iter
    (fun result ->
      Log.debug "Query: %s" (InfluxDB.show_select select) ;
      match result with
      | [] -> Log.debug "No results for this query."
      | _ -> Log.debug "%s" (InfluxDB.show_query_result result))
    result ;
  unit

let query select extract_data =
  match !current_test with
  | None ->
      invalid_arg
        "Long_test.query: not running a test registered with Long_test"
  | Some {title; _} ->
      let rec add_clause (select : InfluxDB.select) =
        match select.from with
        | Select sub_select ->
            {select with from = Select (add_clause sub_select)}
        | Measurement _ -> (
            let where_test : InfluxDB.where = Tag ("test", EQ, title) in
            match select.where with
            | None -> {select with where = Some where_test}
            | Some where -> {select with where = Some (And (where, where_test))}
            )
      in
      unsafe_query (add_clause select) extract_data

module Stats = struct
  type _ t =
    | Int : InfluxDB.func -> int t
    | Float : InfluxDB.func -> float t
    | Pair : 'a t * 'b t -> ('a * 'b) t
    | Convert : 'a t * ('b -> 'a) * ('a -> 'b) -> 'b t

  let count = Int COUNT

  let mean = Float MEAN

  let median = Float MEDIAN

  let stddev = Float STDDEV

  let _2 a b = Pair (a, b)

  let _3 a b c =
    Convert
      ( Pair (a, Pair (b, c)),
        (fun (a, b, c) -> (a, (b, c))),
        fun (a, (b, c)) -> (a, b, c) )

  let rec functions : 'a. 'a t -> _ =
    fun (type a) (stats : a t) ->
     match stats with
     | Int func | Float func -> [func]
     | Pair (a, b) -> functions a @ functions b
     | Convert (stats, _, _) -> functions stats

  let rec get : 'a. _ -> 'a t -> 'a =
    fun (type a) result_data_point (stats : a t) ->
     let result : a =
       match stats with
       | Int func ->
           InfluxDB.get
             (InfluxDB.column_name_of_func func)
             JSON.as_int
             result_data_point
       | Float func ->
           InfluxDB.get
             (InfluxDB.column_name_of_func func)
             JSON.as_float
             result_data_point
       | Pair (a, b) -> (get result_data_point a, get result_data_point b)
       | Convert (stats, _, decode) -> decode (get result_data_point stats)
     in
     result

  let show stats values =
    let rec gather : 'a. 'a t -> 'a -> _ =
      fun (type a) (stats : a t) (values : a) ->
       match stats with
       | Int func -> [(InfluxDB.column_name_of_func func, string_of_int values)]
       | Float func ->
           [(InfluxDB.column_name_of_func func, string_of_float values)]
       | Pair (a, b) ->
           let (v, w) = values in
           gather a v @ gather b w
       | Convert (stats, encode, _) -> gather stats (encode values)
    in
    gather stats values
    |> List.map (fun (name, value) -> sf "%s = %s" name value)
    |> String.concat ", "
end

let get_previous_stats ?limit ?(minimum_count = 3) measurement field stats =
  let stats = Stats.(_2 count) stats in
  let select =
    InfluxDB.(
      select
        (List.map
           (fun func -> Function (func, Field field))
           (Stats.functions stats))
        ~from:
          (Select
             (select
                [Field field]
                ~from:(Measurement measurement)
                ~order_by:Time_desc
                ?limit))
        ~order_by:Time_desc)
  in
  let* result =
    query select @@ fun result ->
    match result with
    | [] -> failwith "InfluxDB result contains no series"
    | _ :: _ :: _ -> failwith "InfluxDB result contains multiple series"
    | [[]] -> failwith "InfluxDB result contains no values"
    | [(_ :: _ :: _)] -> failwith "InfluxDB result contains multiple values"
    | [[value]] ->
        let ((count, _) as stats) = Stats.get value stats in
        if count < minimum_count then None else Some stats
  in
  return (Option.join result)

let get_pending_data_points measurement =
  match !current_test with
  | None ->
      invalid_arg
        "Long_test.get_pending_data_points: not running a test registered with \
         Long_test"
  | Some test ->
      test.data_points
      |> String_map.find_opt measurement
      |> Option.value ~default:[]

type check = Mean | Median

let mean list =
  let count = ref 0 in
  let sum = ref 0. in
  List.iter
    (fun value ->
      incr count ;
      sum := !sum +. value)
    list ;
  !sum /. float !count

let median list =
  let sorted = List.sort Float.compare list |> Array.of_list in
  let count = Array.length sorted in
  if count > 0 then
    if count mod 2 = 0 then
      let i = count / 2 in
      (sorted.(i - 1) +. sorted.(i)) /. 2.
    else sorted.(count / 2)
  else invalid_arg "Long_test.median: empty list"

let check_regression ?(previous_count = 10) ?(minimum_previous_count = 3)
    ?(margin = 0.2) ?(check = Mean) ?(stddev = false) ?data_points measurement
    field =
  if !current_test = None then
    invalid_arg
      "Long_test.check_regression: not running a test registered with Long_test" ;
  let current_values =
    let data_points =
      match data_points with
      | Some list -> list
      | None -> get_pending_data_points measurement
    in
    let get_field (data_point : InfluxDB.data_point) =
      match
        List.assoc_opt field (data_point.first_field :: data_point.other_fields)
      with
      | None | Some (String _) -> None
      | Some (Float f) -> Some f
    in
    List.filter_map get_field data_points
  in
  match current_values with
  | [] -> unit
  | _ :: _ -> (
      let current_value =
        match check with
        | Mean -> mean current_values
        | Median -> median current_values
      in
      let get_previous stats handle_values =
        let* values =
          get_previous_stats
            ~limit:previous_count
            ~minimum_count:minimum_previous_count
            measurement
            field
            stats
        in
        match values with
        | None ->
            Log.debug "Not enough previous data points." ;
            unit
        | Some values ->
            Log.debug
              "Previous data points: %s"
              (Stats.show Stats.(_2 count stats) values) ;
            handle_values values ;
            unit
      in
      let get_previous_with_stddev stats handle_values =
        if stddev then
          get_previous Stats.(_2 stats stddev) @@ fun (count, (values, _)) ->
          handle_values (count, values)
        else get_previous stats handle_values
      in
      let get_previous_and_check name stats =
        get_previous_with_stddev stats
        @@ fun (previous_count, previous_value) ->
        if current_value > previous_value *. (1. +. margin) then
          alert
            "%s(%S.%S) = %g is more than %d%% more than the value for the \
             previous %d measurements, which is %g"
            name
            measurement
            field
            current_value
            (int_of_float (margin *. 100.))
            previous_count
            previous_value
      in
      match check with
      | Mean -> get_previous_and_check "mean" Stats.mean
      | Median -> get_previous_and_check "median" Stats.median)

let check_time_preconditions measurement =
  if !current_test = None then
    invalid_arg "Long_test.time: not running a test registered with Long_test" ;
  if String.contains measurement '\n' then
    invalid_arg "Long_test.time: newline character in measurement"

let time ?previous_count ?minimum_previous_count ?margin ?check ?stddev
    ?(repeat = 1) measurement f =
  check_time_preconditions measurement ;
  if repeat <= 0 then unit
  else
    let data_points = ref [] in
    for _ = 1 to repeat do
      let start = Unix.gettimeofday () in
      f () ;
      let duration = Unix.gettimeofday () -. start in
      let data_point =
        InfluxDB.data_point measurement ("duration", Float duration)
      in
      add_data_point data_point ;
      data_points := data_point :: !data_points
    done ;
    check_regression
      ?previous_count
      ?minimum_previous_count
      ?margin
      ?check
      ?stddev
      ~data_points:!data_points
      measurement
      "duration"

let time_lwt ?previous_count ?minimum_previous_count ?margin ?check ?stddev
    ?(repeat = 1) measurement f =
  check_time_preconditions measurement ;
  if repeat <= 0 then unit
  else
    let data_points = ref [] in
    let* () =
      Base.repeat repeat @@ fun () ->
      let start = Unix.gettimeofday () in
      let* () = f () in
      let duration = Unix.gettimeofday () -. start in
      let data_point =
        InfluxDB.data_point measurement ("duration", Float duration)
      in
      add_data_point data_point ;
      data_points := data_point :: !data_points ;
      unit
    in
    check_regression
      ?previous_count
      ?minimum_previous_count
      ?margin
      ?check
      ?stddev
      ~data_points:!data_points
      measurement
      "duration"

let make_tags team tags =
  match team with None -> "long" :: tags | Some team -> "long" :: team :: tags

(* Warning: [argument] must not be applied at registration. *)
let wrap_body title filename team timeout body argument =
  let test =
    {title; filename; team; data_points = String_map.empty; alert_count = 0}
  in
  current_test := Some test ;
  Lwt.finalize
    (fun () ->
      Lwt.catch
        (fun () ->
          Lwt.finalize (with_timeout timeout (body argument)) send_data_points)
        (fun exn ->
          alert_s ~log:false (Printexc.to_string exn) ;
          raise exn))
    (fun () ->
      current_test := None ;
      unit)

let register ~__FILE__ ~title ~tags ?team ~timeout body =
  if String.contains title '\n' then
    invalid_arg
      "Long_test.register: long test titles cannot contain newline characters" ;
  let tags = make_tags team tags in
  Test.register
    ~__FILE__
    ~title
    ~tags
    (wrap_body title __FILE__ team timeout body)

let register_with_protocol ~__FILE__ ~title ~tags ?team ~timeout body =
  if String.contains title '\n' then
    invalid_arg
      "Long_test.register_with_protocol: long test titles cannot contain \
       newline characters" ;
  let tags = make_tags team tags in
  Protocol.register_test
    ~__FILE__
    ~title
    ~tags
    (wrap_body title __FILE__ team timeout body)

let update_grafana_dashboard (dashboard : Grafana.dashboard) =
  Lwt_main.run
  @@
  match config with
  | {influxdb = Some influxdb_config; grafana = Some grafana_config; _} ->
      let dashboard =
        (* Prefix measurements in queries with the InfluxDB measurement prefix. *)
        let update_panel = function
          | Grafana.Row _ as x -> x
          | Graph graph ->
              Graph
                {
                  graph with
                  queries =
                    List.map
                      (InfluxDB.prefix_measurement influxdb_config)
                      graph.queries;
                }
        in
        {dashboard with panels = List.map update_panel dashboard.panels}
      in
      Grafana.update_dashboard grafana_config dashboard
  | _ -> unit
