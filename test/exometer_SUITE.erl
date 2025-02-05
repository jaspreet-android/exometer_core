%%
%%   This Source Code Form is subject to the terms of the Mozilla Public
%%   License, v. 2.0. If a copy of the MPL was not distributed with this
%%   file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%
%% -------------------------------------------------------------------
-module(exometer_SUITE).

%% common_test exports
-export(
   [
    all/0, groups/0, suite/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2
   ]).

%% test case exports
-export(
   [
    test_std_counter/1,
    test_gauge/1,
    test_fast_counter/1,
    test_crashing_function/1,
    test_wrapping_counter/1,
    test_update_or_create/1,
    test_update_or_create2/1,
    test_default_override/1,
    test_std_histogram/1,
    test_slot_histogram/1,
    test_std_duration/1,
    test_aggregate/1,
    test_history1_slide/1,
    test_history1_slotslide/1,
    test_history4_slide/1,
    test_history4_slotslide/1,
    test_re_register_probe/1,
    test_ext_predef/1,
    test_app_predef/1,
    test_function_match/1,
    test_status/1,
    test_slide_ignore_outdated/1
   ]).

%% utility exports
-export(
   [
    vals/0,
    crash_fun/0
   ]).

-import(exometer_test_util, [majority/2]).

-include_lib("common_test/include/ct.hrl").

%%%===================================================================
%%% common_test API
%%%===================================================================

all() ->
    [
     {group, test_counter},
     {group, test_defaults},
     {group, test_histogram},
     {group, re_register},
     {group, test_setup},
     {group, test_info}
    ].

groups() ->
    [
     {test_counter, [shuffle],
      [
        test_std_counter,
        test_gauge,
        test_fast_counter,
        test_crashing_function,
        test_wrapping_counter
      ]},
     {test_defaults, [shuffle],
      [
       test_update_or_create,
       test_update_or_create2,
       test_default_override
      ]},
     {test_histogram, [shuffle],
      [
       test_std_histogram,
       test_slot_histogram,
       test_std_duration,
       test_aggregate,
       test_history1_slide,
       test_history1_slotslide,
       test_history4_slide,
       test_history4_slotslide,
       test_slide_ignore_outdated
      ]},
     {re_register, [shuffle],
      [
       test_re_register_probe
      ]},
     {test_setup, [shuffle],
      [
       test_ext_predef,
       test_app_predef,
       test_function_match
      ]},
     {test_info, [shuffle],
      [
       test_status
      ]}
    ].

suite() ->
    [].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(Case, Config) when
      Case == test_ext_predef;
      Case == test_function_match ->
    ok = application:set_env(
           stdlib, exometer_predefined,
           {script, file_path("test/data/test_defaults.script")}),
    {ok, StartedApps} = exometer_test_util:ensure_all_started(exometer_core),
    ct:log("StartedApps = ~p~n", [StartedApps]),
    [{started_apps, StartedApps} | Config];
init_per_testcase(test_app_predef, Config) ->
    compile_app1(Config),
    {ok, StartedApps} = exometer_test_util:ensure_all_started(exometer_core),
    ct:log("StartedApps = ~p~n", [StartedApps]),
    Scr = filename:join(filename:dirname(
                          filename:absname(?config(data_dir, Config))),
                        "data/app1.script"),
    ok = application:set_env(app1, exometer_predefined, {script, Scr}),
    [{started_apps, StartedApps} | Config];
init_per_testcase(_Case, Config) ->
    {ok, StartedApps} = exometer_test_util:ensure_all_started(exometer_core),
    ct:log("StartedApps = ~p~n", [StartedApps]),
    [{started_apps, StartedApps} | Config].

end_per_testcase(Case, Config) when
      Case == test_ext_predef;
      Case == test_function_match ->
    ok = application:unset_env(stdlib, exometer_predefined),
    _ = stop_started_apps(Config),
    ok;
end_per_testcase(test_app_predef, Config) ->
    ok = application:unset_env(app1, exometer_predefined),
    ok = application:stop(app1),
    _ = stop_started_apps(Config),
    ok;
end_per_testcase(_Case, Config) ->
    _ = stop_started_apps(Config),
    ok.

stop_started_apps(Config) ->
    [stop_app(App) ||
        App <- lists:reverse(?config(started_apps, Config))].

stop_app(App) ->
    case application:stop(App) of
        ok -> ok;
        {error, {not_started, _}} ->
            ok
    end.

%%%===================================================================
%%% Test Cases
%%%===================================================================
test_std_counter(_Config) ->
    C = [?MODULE, ctr, ?LINE],
    ok = exometer:new(C, counter, []),
    ok = exometer:update(C, 1),
    {ok, [{value, 1}]} = exometer:get_value(C, [value]),
    {ok, [{value, 1}, {ms_since_reset,_}]} = exometer:get_value(C),
    ok.

test_gauge(_Config) ->
    C = [?MODULE, gauge, ?LINE],
    ok = exometer:new(C, gauge, []),
    ok = exometer:update(C, 1),
    timer:sleep(10),
    {ok, [{value, 1}]} = exometer:get_value(C, [value]),
    {ok, [{value, 1}, {ms_since_reset,_}]} = exometer:get_value(C),
    ok = exometer:update(C, 5),
    {ok, [{value, 5}]} = exometer:get_value(C, [value]),
    ok = exometer:reset(C),
    {ok, [{value, 0}, {ms_since_reset,_}]} = exometer:get_value(C),
    ok = exometer:delete(C),
    {error, not_found} = exometer:get_value(C, [value]),
    ok.

test_fast_counter(_Config) ->
    C = [?MODULE, fctr, ?LINE],
    ok = exometer:new(C, fast_counter, [{function, {?MODULE, fc}}]),
    fc(),
    fc(),
    {ok, [{value, 2}]} = exometer:get_value(C, [value]),
    {ok, [{value, 2}, {ms_since_reset, _}]} = exometer:get_value(C),
    ok.

test_crashing_function(_Config) ->
    C1 = [?MODULE, function, ?LINE],
    C2 = [?MODULE, cached_function, ?LINE],
    ok = exometer:new(C1, {function, ?MODULE, crash_fun, [], valie, [value]}, []),
    ok = exometer:new(C2, {function, ?MODULE, crash_fun, [], valie, [value]}, [{cache, 5000}]),
    {ok, {error, unavailable}} = exometer:get_value(C1, [value]),
    {ok, {error, unavailable}} = exometer:get_value(C2, [value]),
    ok.

test_wrapping_counter(_Config) ->
    C = [?MODULE, ctr, ?LINE],
    ok = exometer:new(C, counter, []),
    Max16 = 65534,
    Max32 = 4294967294,
    Max64 = 18446744073709551614,
    Max64p1 = 18446744073709551615,
    Max64p21 = 18446744073709551635,
    ok = exometer:update(C, Max64),
    {ok, [{value, Max64}, {value16, Max16}, {value32, Max32}, {value64, Max64}]} =
      exometer:get_value(C, [value, value16, value32, value64]),
    ok = exometer:update(C, 1),
    {ok, [{value, Max64p1}, {value16, 0}, {value32, 0}, {value64, 0}]} =
      exometer:get_value(C, [value, value16, value32, value64]),
    [ok = exometer:update(C, 1) || _ <- lists:seq(1, 20)],
    {ok, [{value, Max64p21}, {value16, 20}, {value32, 20}, {value64, 20}]} =
      exometer:get_value(C, [value, value16, value32, value64]),
    ok.

test_update_or_create(_Config) ->
    {error, not_found} = exometer:update([a,b,c], 2),
    {error, no_template} = exometer:update_or_create([a,b,c], 10),
    exometer_admin:set_default([a,b,c], counter, []),
    ok = exometer:update_or_create([a,b,c], 3),
    {ok, [{value, 3}]} = exometer:get_value([a,b,c], [value]),
    exometer_admin:set_default([a,'_',d], histogram, []),
    histogram = exometer:info(exometer_admin:find_auto_template([a,b,d]), type),
    counter = exometer:info(exometer_admin:find_auto_template([a,b,c]), type),
    ok.

test_default_override(_Config) ->
    E = [d,e,f],
    E1 = [d,e,f,1],
    E2 = [d,e,f,2],
    undefined = exometer:info(E, status),
    exometer_admin:set_default(E, histogram, [{options,
					       [{histogram_module,
						 exometer_slot_slide},
						{keep_high, 100}]}]),
    exometer:new(E1, histogram, []),
    [{histogram_module, exometer_slot_slide},
     {keep_high, 100}] = exometer:info(E1, options),
    exometer:new(E2, histogram, [{keep_high, 300}]),
    [{histogram_module, exometer_slot_slide},
     {keep_high, 300}] = exometer:info(E2, options),
    exometer:new(E, histogram, [{histogram_module, exometer_slide},
				{'--', [keep_high]}]),
    [{histogram_module, exometer_slide}] =
	exometer:info(E, options),
    ok.

test_update_or_create2(_Config) ->
    C = [b,c,d], Type = counter, Opts = [],
    {error, not_found} = exometer:update(C, 2),
    ok = exometer:update_or_create(C, 3, Type, Opts),
    {ok, [{value, 3}]} = exometer:get_value(C, [value]),
    ok.


test_std_histogram(_Config) ->
    C = [?MODULE, hist, ?LINE],
    ok = exometer:new(C, histogram, [{histogram_module, exometer_slide},
                                     {truncate, false}]),
    [ok = update_(C,V) || V <- vals()],
    {_, {ok,DPs}} = timer:tc(exometer, get_value, [C]),
    [{n,134},{mean,2126866},{min,1},{max,9},{median,2},
     {50,2},{75,3},{90,4},{95,5},{99,8},{999,9}] = scale_mean(DPs),
    ok.

test_slot_histogram(Config) ->
    C = [?MODULE, hist, ?LINE],
    majority(fun test_slot_histogram_/1, [{metric_name, C}|Config]).

test_slot_histogram_({cleanup, Config}) ->
    C = ?config(metric_name, Config),
    exometer:delete(C),
    ct:sleep(200);
test_slot_histogram_(Config) ->
    C = ?config(metric_name, Config),
    ok = exometer:new(C, histogram, [{histogram_module, exometer_slot_slide},
				     {keep_high, 100},
                                     {truncate, false}]),
    [ok = update_(C,V) || V <- vals()],
    {_, {ok,DPs}} = timer:tc(exometer, get_value, [C]),
    %% does not match on mean as it is not stable on travis CI and this configuration
    [{n,_},{mean,_},{min,1},{max,9},{median,2},
     {50,2},{75,3},{90,4},{95,5},{99,8},{999,9}] = scale_mean(DPs),
    ok.

test_std_duration(_Config) ->
    C = [?MODULE, dur, ?LINE],
    ok = exometer:new(C, duration, []),
    [ok = update_duration(C, V) || V <- vals()],
    {_, {ok,DPs}} = timer:tc(exometer, get_value, [C]),
    [{count,134},{last,_},{n,_},{mean,_},{min,_},{max,_},
     {median,_},{50,_},{75,_},{90,_},{95,_},{99,_},{999,_}] = DPs,
    {ok,[{count,134},{last,_}]} = exometer:get_value(C, [count,last]),
    {ok,[{mean,_},{count,_},{max,_}]} =
	exometer:get_value(C, [mean,count,max]),
    ok.

update_duration(C, V) ->
    exometer:update(C, timer_start),
    timer:sleep(V),
    exometer:update(C, timer_end).

test_aggregate(_Config) ->
    K = ?LINE,
    ok = exometer:new(E1 = [?MODULE, K, a, 1], gauge, []),
    ok = exometer:new(E2 = [?MODULE, K, a, 2], gauge, []),
    ok = exometer:new(E3 = [?MODULE, K, a, 3], gauge, []),
    ok = exometer:new(E4 = [?MODULE, K, b, 2], histogram, []),
    [update_(E,V) || {E,V} <- [{E1,3},{E2,4},{E3,5}|
			       [{E4,1} || _ <- lists:seq(1,10)]]],
    [{value,12}] = exometer:aggregate([{ {[?MODULE,K,a,'_'],'_','_'},[],[true] }], [value]),
    [{50,1},{75,1},{90,1},{95,1},{99,1},{999,1},{max,1},{mean,1},{median,1},{min,1},
     {ms_since_reset,_},{n,_},
     {value,12}] =
	exometer:aggregate([{ {[?MODULE,K,'_','_'],'_','_'},[],[true] }], default),
    ok.

test_history1_slide(_Config) ->
    test_history(1, slide, file_path("test/data/puts_time_hist1.bin")).

test_history1_slotslide(_Config) ->
    test_history(1, slot_slide, file_path("test/data/puts_time_hist1.bin")).

test_history4_slide(_Config) ->
    test_history(4, slide, file_path("test/data/puts_time_hist4.bin")).

test_history4_slotslide(_Config) ->
    test_history(4, slot_slide, file_path("test/data/puts_time_hist4.bin")).

test_re_register_probe(_Config) ->
    K = ?LINE,
    ok = exometer:re_register(S1 = [?MODULE, K, s, 1], spiral, []),  % re_register as new/3
    P1 = exometer:info(S1, ref),
    MRef = monitor(process, P1),  % in this specific case, we know P1 is a process
    true = erlang:is_process_alive(P1),
    ok = exometer:re_register(S1, spiral, []),
    P2 = exometer:info(S1, ref),
    true = (P1 =/= P2),
    %% removal of old probe is asynchronous ...
    %% TODO: some more sophistication in replacing the old instance
    %% might be called for.
    receive
        {'DOWN', MRef, _, _, _} ->
            ok
    after 1000 ->
            error(timeout)
    end,
    true = erlang:is_process_alive(P2),
    ok.

file_path(F) ->
    filename:join(code:lib_dir(exometer_core), F).


test_ext_predef(_Config) ->
    {ok, [{total, _}]} = exometer:get_value([preset, func], [total]),
    [total, processes, ets, binary, atom] =
	exometer:info([preset, func], datapoints),
    ok.

test_app_predef(Config) ->
    ok = application:start(app1),
    [{[app1,c,1],_,_},{[app1,c,2],_,_}] =
	exometer:find_entries([app1,'_','_']),
    File = filename:join(
	     filename:dirname(filename:absname(?config(data_dir,Config))),
	     "data/app1_upg.script"),
    application:set_env(app1, exometer_predefined, {script,File}),
    ok = exometer:register_application(app1),
    [{[app1,d,1],_,_}] =
	exometer:find_entries([app1,'_','_']),
    ok.

test_function_match(_Config) ->
    {ok, [{gcs, _}]} = exometer:get_value([preset, match], [gcs]),
    [gcs] = exometer:info([preset, match], datapoints),
    ok.

test_status(_Config) ->
    Opts1 = [{module, exometer_histogram}],
    DPs1 = exometer_histogram:datapoints(),
    exometer:new(M1 = [?MODULE,hist,?LINE], histogram, Opts1),
    enabled = exometer:info(M1, status),
    M1 = exometer:info(M1, name),
    Opts1 = exometer:info(M1, options),
    DPs1 = exometer:info(M1, datapoints),
    Vals = [{DP,0} || DP <- DPs1],
    [{name, M1},
     {type, histogram},
     {behaviour, undefined},
     {module, exometer_histogram},
     {status, enabled},
     {cache, 0},
     {value, Vals},
     {timestamp, undefined},
     {options, Opts1},
     {ref, _}] = exometer:info(M1),
    %% disable metric
    ok = exometer:setopts(M1, [{status, disabled}]),
    disabled = exometer:info(M1, status),
    undefined = exometer:info(M1, datapoints),
    M1 = exometer:info(M1, name),
    undefined = exometer:info(M1, value),
    Opts2 = Opts1 ++ [{status, disabled}],
    [{name, M1},
     {type, histogram},
     {behaviour, undefined},
     {module, exometer_histogram},
     {status, disabled},
     {cache, undefined},
     {value, undefined},
     {timestamp, undefined},
     {options, Opts2},
     {ref, undefined}] = exometer:info(M1),
    ok.

%% Ensure a slide ignores values which are outdated as per its configuration of
%% time_span. This is important in cases with low update frequencies.
test_slide_ignore_outdated(_Config) ->
   M = [?MODULE, hist, ?LINE],

   ok = exometer:new(
          M, ad_hoc, [{module, exometer_histogram},
                      {type, histogram},
                      {histogram_module, exometer_slide},
                      {time_span, 5}]),
   % check that no entries exist
   {ok, V1} = exometer:get_value(M),
   0 = proplists:get_value(n, V1),

   % add entry
   ok = exometer:update(M, 1234),

   % check that new entry exists
   {ok, V2} = exometer:get_value(M),
   1 = proplists:get_value(n, V2),

   % wait
   timer:sleep(10),

   % check that entries have expired
   {ok, V3} = exometer:get_value(M),
   0 = proplists:get_value(n, V3),

   ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

test_history(N, slide, F) ->
    M = [?MODULE, hist, ?LINE],
    ok = exometer:new(
           M, ad_hoc, [{module, exometer_histogram},
                       {type, histogram},
                       {histogram_module, exometer_slide}]),
    RefStats = load_data(F, M),
    ct:log("history(~w,s): ~p~n"
           "reference:   ~p~n", [N, exometer:get_value(M),
                                 subset(RefStats)]),
    ok;
test_history(N, slot_slide, F) ->
    M = [?MODULE, hist, ?LINE],
    ok = exometer:new(
           M, ad_hoc, [{module, exometer_histogram},
                       {type, histogram},
                       {histogram_module, exometer_slot_slide},
                       {slot_period, 1}]),
    RefStats = load_data(F, 2000, M),
    {T, {ok, Val}} = timer:tc(exometer,get_value,[M]),
    Subset = subset(RefStats),
    Error = calc_error(Val, Subset),
    ct:log("time: ~p~n"
           "history(~w,ss): ~p~n"
           "reference:    ~p~n"
           "error: ~p~n", [T, N, Val, Subset, Error]),
    ok.

vals() ->
    lists:append(
      [lists:duplicate(50, 1),
       lists:duplicate(50, 2),
       lists:duplicate(20, 3),
       lists:duplicate(5, 4),
       lists:duplicate(5, 5),
       [6,7,8,9]]).

update_(C, V) ->
    exometer:update(C, V).

scale_mean([]) ->
    [];
scale_mean([{mean,M}|T]) ->
    [{mean, round(M*1000000)}|T];
scale_mean([H|T]) ->
    [H|scale_mean(T)].

fc() ->
    ok.

crash_fun() ->
    throw(error),
    [{value, 1}].

load_data(F, M) ->
    ct:log("load_data(~s,...)", [F]),
    ct:log("CWD = ~p", [element(2, file:get_cwd())]),
    {ok, [Values]} = file:consult(F),
    Stats = bear:get_statistics(Values),
    _T1 = os:timestamp(),
    _ = [ok = exometer:update(M, V) || V <- Values],
    _T2 = os:timestamp(),
    Stats.

load_data(F, Rate, M) ->
    {ok, [Values]} = file:consult(F),
    Stats = bear:get_statistics(Values),
    pace(Rate, fun([V|Vs]) ->
                       ok = exometer:update(M, V),
                       {more, Vs};
                  ([]) ->
                       {done, ok}
               end, Values),
    Stats.

pace(OpsPerSec, F, St) ->
    PerSlot = OpsPerSec div 20, % 5 ms
    L = lists:seq(1,PerSlot),
    TRef = erlang:start_timer(5, self(), shoot),
    case shoot(F, St, L) of
        {done, Res} ->
            erlang:cancel_timer(TRef),
            Res;
        {more, St1} ->
            keep_pace(TRef, F, St1, L)
    end.

keep_pace(TRef, F, St, L) ->
    receive {timeout, TRef, shoot} ->
                TRef1 = erlang:start_timer(5, self(), shoot),
                case shoot(F, St, L) of
                    {done, Res} ->
                        erlang:cancel_timer(TRef1),
                        Res;
                    {more, St1} ->
                        keep_pace(TRef1, F, St1, L)
                end
    after 100 ->
              timeout
    end.

shoot(F, St, [_|T]) ->
    case F(St) of
        {done, _} = Done ->
            Done;
        {more, St1} ->
            shoot(F, St1, T)
    end;
shoot(_, St, []) ->
    {more, St}.

subset(Stats) ->
    lists:map(
      fun(mean) -> {mean, proplists:get_value(arithmetic_mean, Stats)};
         (K) when is_atom(K) -> lists:keyfind(K, 1, Stats);
         (P) when is_integer(P) ->
              lists:keyfind(P, 1, proplists:get_value(percentile,Stats,[]))
      end, [n,mean,min,max,median,50,75,90,95,99,999]).

calc_error(Val, Ref) ->
    lists:map(
      fun({{K,V}, {K,R}}) ->
              {K, abs(V-R)/R}
      end, lists:zip(Val, Ref)).


compile_app1(Config) ->
    DataDir = filename:absname(?config(data_dir, Config)),
    Dir = filename:join(filename:dirname(DataDir), "app1"),
    ct:log("Dir = ~p~n", [Dir]),
    Src = filename:join(Dir, "src"),
    Ebin = filename:join(Dir, "ebin"),
    filelib:fold_files(
      Src, ".*\\.erl\$", false,
      fun(F,A) ->
	      CompRes = compile:file(filename:join(Src,F),
				     [{outdir, Ebin}]),
	      ct:log("Compile (~p) -> ~p~n", [F, CompRes]),
	      A
      end, ok),
    %% Res = os:cmd(["(cd ", Dir, " && rebar compile)"]),
    %% ct:log("Rebar res = ~p~n", [Res]),
    Path = filename:join(Dir, "ebin"),
    PRes = code:add_pathz(Path),
    ct:log("add_pathz(~p) -> ~p~n", [Path, PRes]).
