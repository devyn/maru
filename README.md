# Maru

Maru (丸; circle) is a computational task distribution system.

## Data model

### Groups

Tasks are represented by groups, which contain jobs and information about what is needed to complete the jobs.

### Jobs

Jobs are individual pieces of work needed to complete a job group. A job group may represent the rendering of an animation, for example, and each job it contains represent individual frames of the animation.

## Masters and workers

**Masters** track and manage jobs and respond to requests for jobs from workers.

**Workers** request jobs from masters, perform them, and send the output back to the master they came from.

They share a many-to-many relationship. That is, masters may give jobs to any number of workers, and workers may request jobs from any number of masters.

## Worker config example

```yaml
---
wait_time: 60                    # Default: 30 seconds
group_expiry: 86400              # Default: 7200 seconds (2 hours)
keep_temp: true                  # Default: false
temp_dir: /home/compute/worker1/ # Default: /tmp/maru.<PID>
masters:
- http://localhost:3202/
- http://compute.example.com/
kinds:
- blender_animation
- prime_number
plugins:
- maru/worker/plugins/blender_animation
- maru/worker/plugins/prime_number
```
