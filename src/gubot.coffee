# Description:
#   Hubot RiffRaff
#
# Commands:
#   hubot deploy APP [build N|branch B] to STAGE - deploy an app
#   hubot rollback APP in STAGE                  - rollback an app deployment
#   hubot builds APP                             - list recent builds for an app
#   hubot info                                   - show deployment configuration
#
# Author:
#   Sébastien Cevey
#

fs = require 'fs'

axios = require 'axios'
yaml = require 'yaml-js'

RiffRaff = require './riffraff'
TeamCity = require './teamcity'


Array::includes    ?= (x) -> @indexOf(x) != -1


module.exports = (robot) ->

  config = yaml.load fs.readFileSync('./gubot.config.yml')

  riffraff = new RiffRaff(config.riffraff.uri)
  teamcity = new TeamCity(config.teamcity.uri, config.teamcity.user, config.teamcity.pass)

  stacks = config.stacks


  # helper method to get sender of the message
  get_username = (response) ->
    "@#{response.message.user.name}"

  # helper method to get user ID of sender of the message
  get_user_id = (response) ->
    "@#{response.message.user.id}"

  # helper method to get channel of originating message
  get_channel = (response) ->
    if response.message.room == response.message.user.name
      "@#{response.message.room}"
    else
      "##{response.message.room}"

  get_stack = (res) ->
    channel = get_channel(res)
    stacks.filter((stack) -> stack.channels.includes(channel))[0]


  with_riffraff_key = (res, user_id, func) ->
    key = robot.brain.get("riffraff.key.#{user_id}")
    if key
      func(key)
    else
      res.send "No RiffRaff API key configured, please create a token at #{riffraff.api_key_page()} and run `/msg gubot configure riffraff TOKEN`"


  start_deploy = (key, stack, app, build_no, stage, res) ->
    riffraff.request_deploy(key, stack, app, build_no, stage)
      .then (resp) ->
        logUrl = resp.data.response.logURL
        res.send "Deploying #{app} (##{build_no}) to #{stage}: #{logUrl}"
        # TODO: [+] show branch being deployed
      .catch (err) ->
        res.send "Ooops, failed to deploy #{app} (##{build_no}) to #{stage}: #{JSON.stringify(err.data)}"


  robot.respond /configure riffraff (.+)/, (res) ->
    key = res.match[1]
    nickname = get_username(res)
    user_id = get_user_id(res)
    if key == '-'
      robot.brain.remove("riffraff.key.#{user_id}")
      res.send "Your secrets have been erased, #{res.message.user.name}!"
    else
      robot.brain.set("riffraff.key.#{user_id}", key)
      res.send "Thanks for that, #{res.message.user.name}!  [`/msg gubot configure riffraff -` to remove]"


  robot.respond /info/, (res) ->
    stack = get_stack(res)

    group_str = ''
    for name, apps of stack.groups
      apps_str = apps.join(' ')
      group_str += "- #{name}: #{apps_str}\n"

    res.send "Stack name: #{stack.name}\n" +
             "Groups:\n#{group_str}"


  robot.respond /builds (.+)/, (res) ->
    # TODO: if no argument, use default_group
    app = res.match[1]
    stack = get_stack(res)

    teamcity.get_builds(stack.name, app)
      .then (builds) ->
        for build in builds
          # FIXME: more info (date, started by, etc)
          res.send "##{build.number}: #{build.branchName} (#{build.status})"


  robot.respond /rollback ([-\w]+?) in ([-\w]+)/, (res) ->
    # TODO: validate app, stage?
    [__, app_name, stage] = res.match

    stage = stage.toUpperCase()

    user_id = get_user_id(res)
    stack = get_stack(res)

    if stack.groups[app_name]
      apps = stack.groups[app_name]
    else
      apps = app_name.split(',')

    with_riffraff_key res, user_id, (key) ->
      for app in apps
        do (app) ->
          riffraff.get_deploy_history(key, stack.name, app, stage)
            .then (deploys) ->
              successful_deploys = deploys.filter((deploy) -> deploy.status == "Completed")
              previous_deploy = successful_deploys[1]
              previous_build = previous_deploy && previous_deploy.build
              start_deploy(key, stack.name, app, previous_build, stage, res)


  # TODO: if /msg, no channel context - require explicit or default?
  robot.respond /deploy ([-\w]+?) (?:build #?(\d+) |branch ([-\w]+?) )?to ([-\w]+)/, (res) ->
    # TODO: validate app, stage?
    [__, app_name, build_no, branch, stage] = res.match

    stage = stage.toUpperCase()

    user_id = get_user_id(res)
    stack = get_stack(res)

    is_topic_branch = branch != undefined && branch != 'master'
    has_build_no = build_no != undefined

    if stage == 'PROD' && (is_topic_branch || has_build_no)
      res.send "#{phrases_no()} Only latest master can be deployed to PROD."
      return

    # TODO: [+] allow deploying previously deployed build (rollback)

    if stack.groups[app_name]
      apps = stack.groups[app_name]
    else
      apps = app_name.split(',')

    if apps.length > 1 && build_no
      res.send "Build number doesn't make sense with multiple apps, does it?"
      return

    with_riffraff_key res, user_id, (key) ->
      for app in apps
        do (app) ->
          if build_no
            start_deploy(key, stack.name, app, build_no, stage, res)
          else if branch
            teamcity.get_last_build(stack.name, app, branch)
              .then (build_no) ->
                start_deploy(key, stack.name, app, build_no, stage, res)
          else
            teamcity.get_last_build(stack.name, app)
              .then (build_no) ->
                console.log("GOT", build_no)
                start_deploy(key, stack.name, app, build_no, stage, res)
              .catch (err) ->
                console.log("GOT", err)
            # TODO: check if currently deploying
            # TODO: only deploy if different version from current (allow force)

  # TODO: [++] list changes missing from $STAGE (master -> $STAGE)
  # TODO: [+] list deploy history
  # TODO: list branches available
  # TODO: list ASG with min/max/desired capacity - !! if desired != min


  robot.catchAll (res) ->
    if /^gubot:? /.test(res.message.text)
      res.send "#{phrases_what()}  [gubot: help]"



  rand = (excl_max) ->
    Math.floor(Math.random() * excl_max)

  one_of = (arr...) -> () ->
    random_index = rand(arr.length)
    arr[random_index]

  phrases_what = one_of(
    "I beg your pardon?",
    "You're simply not making any sense",
    "What?",
    "What do you mean?",
    "Come again?",
    "Hahaha... wait what?",
    "Uh?",
    "Er, what?",
    "Sorry, what?",
    "Uh huh?"
  )

  phrases_no = one_of(
    "I don't think so.",
    "Yeah right.",
    "How about no?",
    "Nope.",
    "Sorry mate.",
    "Yes but no.",
    "Over my dead body."
  )
