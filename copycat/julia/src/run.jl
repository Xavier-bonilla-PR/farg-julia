# Mirrors copycat/copycat.py (the non-GUI parts).

report_answer(::Reporter, answer) = nothing
report_answer(::SimpleReporter, answer) = println(
    "Answered $(answer.answer) (time $(answer.time), " *
    "final temperature $(round(answer.temp; digits=1)))")

struct Answer
    answer::String
    temp::Float64
    time::Int
end

function Copycat(; rng_seed = nothing, reporter::Reporter = NullReporter())
    cc = Copycat(nothing)
    cc.random = Randomness(rng_seed)
    cc.slipnet = build_slipnet()
    cc.temperature = Temperature()
    cc.reporter = reporter
    cc.lastUpdate = -Inf
    cc.coderack = Coderack(cc)
    cc.workspace = Workspace(cc)
    return cc
end

function update_workspace!(cc::Copycat, currentTime::Int)
    updateEverything!(cc.workspace)
    updateCodelets!(cc.coderack)
    update!(cc.slipnet, cc.random)
    update!(cc.temperature, getUpdatedTemperature(cc.workspace))
    cc.lastUpdate = currentTime
end

function mainLoop!(cc::Copycat)
    currentTime = cc.coderack.codeletsRun
    tryUnclamp!(cc.temperature, currentTime)
    # Every 5 codelets, we update the workspace.
    if currentTime >= cc.lastUpdate + 5
        update_workspace!(cc, currentTime)
    end
    chooseAndRunCodelet!(cc.coderack)
end

"""Run one trial of the copycat algorithm."""
function runTrial!(cc::Copycat)
    reset!(cc.coderack)
    reset!(cc.slipnet)
    reset!(cc.temperature)
    reset!(cc.workspace)
    while cc.workspace.finalAnswer === nothing
        mainLoop!(cc)
    end
    answer = Answer(cc.workspace.finalAnswer::String,
                    cc.temperature.last_unclamped_value,
                    cc.coderack.codeletsRun)
    report_answer(cc.reporter, answer)
    return answer
end

mutable struct AnswerStats
    count::Int
    sumtemp::Float64
    sumtime::Float64
end

"""Result of `run!`: answers in first-seen order, matching Python dict order."""
struct RunResult
    keys::Vector{String}
    stats::Dict{String,AnswerStats}
end

avgtemp(r::RunResult, k) = r.stats[k].sumtemp / r.stats[k].count
avgtime(r::RunResult, k) = r.stats[k].sumtime / r.stats[k].count

function run!(cc::Copycat, initial, modified, target, iterations::Int;
              formula::Symbol = :pbest)
    resetWithStrings!(cc.workspace, initial, modified, target)
    keys = String[]
    stats = Dict{String,AnswerStats}()
    useAdj!(cc.temperature, formula)
    for _ in 1:iterations
        answer = runTrial!(cc)
        st = get(stats, answer.answer, nothing)
        if st === nothing
            st = AnswerStats(0, 0.0, 0.0)
            stats[answer.answer] = st
            push!(keys, answer.answer)
        end
        st.count += 1
        st.sumtemp += answer.temp
        st.sumtime += answer.time
    end
    return RunResult(keys, stats)
end
