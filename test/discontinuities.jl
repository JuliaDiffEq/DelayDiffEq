using DelayDiffEq, DiffEqProblemLibrary, Base.Test


dde_int = init(prob_dde_2delays, MethodOfSteps(BS3()))

@test dde_int.tracked_discontinuities == [Discontinuity(0., 0)]

solve!(dde_int)

# calculated discontinuities
discs = [Discontinuity(t, order) for (t, order) in
         ((0., 0), (1/5, 1), (1/3, 1), (2/5, 2), (8/15, 2), (3/5, 3),
          (2/3, 2), (11/15, 3), (13/15, 3))]

for (tracked, disc) in zip(dde_int.tracked_discontinuities, discs)
    @test tracked.t ≈ disc.t && tracked.order == disc.order
end

a = Discontinuity(1, 3)

@test a > 0
@test a < 2
@test a == 1

b = Discontinuity(2.0, 2)

@test !(a > b)
@test a < b
@test a != b

c = Discontinuity(1.0, 2)

@test a > c
@test !(a < c)
@test a != c
