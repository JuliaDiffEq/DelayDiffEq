function init{uType,tType,isinplace,algType<:AbstractMethodOfStepsAlgorithm,lType}(
  prob::AbstractDDEProblem{uType,tType,lType,isinplace},
  alg::algType,timeseries_init=uType[],ts_init=tType[],ks_init=[];
  d_discontinuities = tType[],
  dtmax=tType(7*minimum(prob.lags)),
  dt = tType(0),
  kwargs...)

  # Add to the discontinuties vector the lag locations
  d_discontinuities = [d_discontinuities;compute_discontinuity_tree(prob.lags,alg,prob.tspan[1])]

  # If it's constrained, then no Picard iteration, and thus `dtmax` should match max lag size
  if isconstrained(alg)
    dtmax = min(dtmax,prob.lags...)
  end

  tTypeNoUnits   = typeof(recursive_one(prob.tspan[1]))

  # Bootstrap the Integrator Using An ODEProblem
  ode_prob = ODEProblem(prob.f,prob.u0,prob.tspan;iip=isinplace)
  integrator = init(ode_prob,alg.alg;dt=1,initialize_integrator=false,
                    d_discontinuities=d_discontinuities,
                    dtmax=dtmax,
                    kwargs...)
  h = HistoryFunction(prob.h,integrator.sol,integrator)
  if isinplace
    dde_f = (t,u,du) -> prob.f(t,u,h,du)
  else
    dde_f = (t,u) -> prob.f(t,u,h)
  end

  if typeof(alg.alg) <: OrdinaryDiffEqCompositeAlgorithm
    id = OrdinaryDiffEq.CompositeInterpolationData(integrator.sol.interp,dde_f)
  else
    id = OrdinaryDiffEq.InterpolationData(integrator.sol.interp,dde_f)
  end

  if typeof(alg.alg) <: OrdinaryDiffEqCompositeAlgorithm
    sol = build_solution(prob,
                         integrator.sol.alg,
                         integrator.sol.t,
                         integrator.sol.u,
                         dense=integrator.sol.dense,
                         k=integrator.sol.k,
                         interp=id,
                         alg_choice=integrator.sol.alg_choice,
                         calculate_error = false)
  else
    sol = build_solution(prob,
                         integrator.sol.alg,
                         integrator.sol.t,
                         integrator.sol.u,
                         dense=integrator.sol.dense,
                         k=integrator.sol.k,
                         interp=id,
                         calculate_error = false)
  end


  h2 = HistoryFunction(prob.h,sol,integrator)
  if isinplace
    dde_f2 = (t,u,du) -> prob.f(t,u,h2,du)
  else
    dde_f2 = (t,u) -> prob.f(t,u,h2)
  end

  if dt == zero(dt) && integrator.opts.adaptive
    ode_prob = ODEProblem(dde_f2,prob.u0,prob.tspan)
    dt = tType(OrdinaryDiffEq.ode_determine_initdt(prob.u0,prob.tspan[1],
              integrator.tdir,minimum(prob.lags),integrator.opts.abstol,
              integrator.opts.reltol,integrator.opts.internalnorm,
              ode_prob,OrdinaryDiffEq.alg_order(alg)))
  end
  integrator.dt = dt

  if typeof(alg.fixedpoint_abstol) <: Void
    fixedpoint_abstol_internal = map(eltype(uType),integrator.opts.abstol)
  else
    fixedpoint_abstol_internal = map(eltype(uType),alg.fixedpoint_abstol)
  end
  if typeof(alg.picardnorm) <: Void
    picardnorm = integrator.opts.internalnorm
  end


  uEltypeNoUnits = typeof(recursive_one(integrator.u))

  if typeof(alg.fixedpoint_reltol) <: Void
    fixedpoint_reltol_internal = map(uEltypeNoUnits,integrator.opts.reltol)
  else
    fixedpoint_reltol_internal = map(uEltypeNoUnits,alg.fixedpoint_reltol)
  end
  if typeof(integrator.u) <: AbstractArray
    u_cache = similar(integrator.u)
    uprev_cache = similar(integrator.u)
  else
    u_cache = oneunit(eltype(uType))
    uprev_cache = oneunit(eltype(uType))
  end
  
  # for real numbers nlsolve is used for Anderson acceleration of fixed-point iteration which creates vectors of residuals
  if eltype(integrator.u) <: Real
    resid = nothing
  elseif typeof(integrator.u) <: AbstractArray
    resid = similar(integrator.u,uEltypeNoUnits)
  else
    resid = one(uEltypeNoUnits)
  end

  dde_int = DDEIntegrator{typeof(integrator.alg),
                             uType,tType,
                             typeof(fixedpoint_abstol_internal),
                             typeof(fixedpoint_reltol_internal),
                             typeof(resid),
                             tTypeNoUnits,typeof(integrator.tdir),
                             typeof(integrator.k),typeof(sol),
                             typeof(integrator.rate_prototype),
                             typeof(dde_f2),typeof(integrator.prog),
                             typeof(integrator.cache),
                             typeof(integrator),typeof(prob),
                             typeof(picardnorm),
                             typeof(integrator.opts)}(
      sol,prob,integrator.u,integrator.k,integrator.t,integrator.dt,
      dde_f2,integrator.uprev,integrator.tprev,u_cache,uprev_cache,
      fixedpoint_abstol_internal,fixedpoint_reltol_internal,
      resid,picardnorm,alg.max_fixedpoint_iters,alg.m,
      integrator.alg,integrator.rate_prototype,integrator.notsaveat_idxs,integrator.dtcache,
      integrator.dtchangeable,integrator.dtpropose,integrator.tdir,
      integrator.EEst,integrator.qold,integrator.q11,
      integrator.iter,integrator.saveiter,
      integrator.saveiter_dense,integrator.prog,integrator.cache,
      integrator.kshortsize,integrator.just_hit_tstop,integrator.accept_step,
      integrator.isout,
      integrator.reeval_fsal,integrator.u_modified,integrator.opts,integrator) # Leave off fsalfirst, fasllast, first_iteration, and iterator

  initialize!(dde_int)
  initialize!(integrator.opts.callback,integrator.t,integrator.u,dde_int)
  dde_int
end

function solve!(dde_int::DDEIntegrator)
  @inbounds while !isempty(dde_int.opts.tstops)
    while dde_int.tdir*dde_int.t < dde_int.tdir*top(dde_int.opts.tstops)
      loopheader!(dde_int)
      perform_step!(dde_int)
      loopfooter!(dde_int)
      if isempty(dde_int.opts.tstops)
        break
      end
    end
    handle_tstop!(dde_int)
  end

  postamble!(dde_int)
  if has_analytic(dde_int.prob.f)
    u_analytic = [dde_int.prob.f(Val{:analytic},t,dde_int.sol[1]) for t in dde_int.sol.t]
    errors = Dict{Symbol,eltype(dde_int.u)}()
    sol = build_solution(dde_int.sol::AbstractODESolution,u_analytic,errors)
    calculate_solution_errors!(sol;fill_uanalytic=false,timeseries_errors=dde_int.opts.timeseries_errors,dense_errors=dde_int.opts.dense_errors)
    sol.retcode = :Success
    return sol
  else
    dde_int.sol.retcode = :Success
    return dde_int.sol
  end
end

function solve{uType,tType,isinplace,algType<:AbstractMethodOfStepsAlgorithm,lType}(
  prob::AbstractDDEProblem{uType,tType,lType,isinplace},
  alg::algType,timeseries_init=uType[],ts_init=tType[],ks_init=[];kwargs...)

  integrator = init(prob,alg,timeseries_init,ts_init,ks_init;kwargs...)
  solve!(integrator)
end
