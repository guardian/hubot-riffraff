axios = require 'axios'


basic_auth = (user, pass) ->
  'Basic ' + new Buffer(user + ':' + pass).toString('base64')

class TeamCity
  constructor: (@api_uri, @username, @password) ->

  api_request_uri: (path) -> "#{@api_uri}/httpAuth/app/rest#{path}"

  auth_header: () -> { Authorization: basic_auth(@username, @password) }

  get_build_type_id: (project, name) ->
    url = @api_request_uri "/buildTypes/project:#{project},name:#{name}"
    axios.get(url, {headers: @auth_header()})
      .then (resp) ->
        resp.data.id

  get_builds: (project, name, branch) ->
    self = this
    branch_filter = (branch && ",branch:#{branch}") || ''
    @get_build_type_id(project, name)
      .then (buildTypeId) ->
        url = self.api_request_uri "/builds?locator=buildType:#{buildTypeId},count:10#{branch_filter}"
        axios.get(url, {headers: self.auth_header()})
      .then (resp) ->
        resp.data.build

  get_last_build: (project, name, branch) ->
    @get_builds(project, name)
      .then (builds) ->
        successful_builds = builds.filter (build) -> build.status == 'SUCCESS'
        last_build = successful_builds[0]
        last_build && last_build.number


module.exports = TeamCity
