(local test (require :test))
(local sched (require :sched))

(test.case "rig globals are available"
  (fn []
    (test.equal (type rig) :table)
    (test.equal (type rig.argv) :table)
    (test.equal (type (. rig.argv 0)) :string)
    (test.truthy (> (# (. rig.argv 0)) 0))))

(test.case "scheduler can run a spawned task"
  (fn []
    (local scheduler (sched.create "test scheduler"))
    (var ran false)

    (scheduler:activate)
    (sched.spawn (fn []
                   (set ran true)))
    (scheduler:drain)
    (scheduler:deactivate)

    (test.truthy ran)))
