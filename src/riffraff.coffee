axios = require 'axios'

class RiffRaff
  constructor: (@api_uri) ->

  api_request_uri: (path) -> "#{@api_uri}/api#{path}"

  api_key_page: () -> "#{@api_uri}/apiKeys/list"

  get_deploy_history: (key, stack, app, stage) ->
    project = [stack, app].join('::')
    url = @api_request_uri "/history"
    axios.get(url, {
      responseType: 'json',
      params:
        projectName: project,
        stage: stage,
        key: key
    }).then (resp) ->
      # return deploys
      resp.data.response.results

  request_deploy: (key, stack, app, build_no, stage) ->
    project = [stack, app].join('::')
    url = @api_request_uri "/deploy/request"
    deploy_request = {
      project: project,
      build: build_no,
      stage: stage
    }
    axios.post(url, deploy_request, {
      responseType: 'json',
      params:
        key: key
    })


module.exports = RiffRaff
