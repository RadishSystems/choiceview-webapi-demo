# webapidemo.rb
# Simple Web Api demo.
require 'rubygems'
require 'json'
require 'rest_client'

hostUri = 'http://cvnet2.radishsystems.com/ChoiceView/ivr/'

session_resource = nil
message_resource = nil
session_data = nil

answer

log 'Answered the call: $currentCall.callerId'

# Start the ChoiceView session
say 'Welcome to the ChoiceView IVR Developer demonstration. Please wait while the ChoiceView session starts.'

signalUri = "https://api.tropo.com/1.0/sessions/#{$currentCall.sessionId}/signals?action=signal&value="

begin
# Send the POST request that starts the session in background
Thread.abort_on_exception = true
postThread = Thread.new do
  log 'Sending POST request to start ChoiceView session'
  RestClient.post 'https://cvnet2.radishsystems.com/ivr/api/sessions',
    JSON(
      'callerId' => $currentCall.callerID, 
      'callId' => $currentCall.id,
      'stateChangeUri' => signalUri + 'state_change',
      'newMessageUri' => signalUri + 'new_message'
    ),
    { :content_type => :json, :accept => :json } do |response, request, result, &block|
      case response.code
      when 201
        log '----- Session started -----'
        session_resource = RestClient::Resource.new response.headers[:location]
        session_data = JSON response.to_s
        log 'Session resource: ' + session_resource.inspect
        log 'Session representation: ' + session_data.inspect
        msgUriIndex = session_data['links'].find_index { |link| link['rel'].end_with?('controlmessage') }
        message_resource = RestClient::Resource.new session_data['links'][msgUriIndex]['href'] if msgUriIndex
        log 'Message resource: ' + message_resource.inspect
      else
        raise 'Cannot start session - status code: ' + response.code.to_s
      end
    end

  # This will go away - signal should be sent by API, not the client
  if session_data['status'] == 'connected'
    log 'Send state_change signal to main thread'
    RestClient.get signalUri + 'state_change' do |response, request, result, &block|
      case response.code
      when 200
        log '----- Signal sent -----'
        log 'Signal response: ' + response.to_s
      else
        log 'Cannot send signal: status code: ' + response.code.to_s
      end
    end
  end
end

# Tell the user to start the ChoiceView session
result = ask 'Go to the main screen of your mobile device, click on the ChoiceView client icon, then press start', {
  :allowSignals => [ 'state_change' ],
  :choices => '[1 DIGIT]',
  :mode => 'dtmf',
  :attempts => 3,
  :timeout => 10.0
}

# wait here until POST thread initializes the globals
postThread.join

rescue Exception
  say 'Cannot connect to the ChoiceView server at this time.  Please try again later.'
  log "Exception while connecting to ChoiceView switch: #{$!}"
  raise
end

# Send the button demo page and loop until the user stops the demo
if result.name == 'signal' || session_data
  until session_data['status'] == 'disconnected'
    case session_data['status']
    when 'interrupted'
      result = ask 'Waiting for the mobile device to reconnect.', {
        :allowSignals => [ 'state_change' ],
        :choices => '[1 DIGIT]',
        :mode => 'dtmf',
        :attempts => 5,
        :timeout => 10.0,
        :onSignal => lambda do |signal|
          if signal.value == 'state_change'
            session_data = JSON(session_resource.get(:accept => :json).to_s)
            log 'Session respresentation: ' + session_data.inspect
            say 'Device has reconnected...' if session_data['status'] == 'connected'
          end
        end
      }
      log "Interrupted ask result: name is #{result.name}, value is #{result.value}."
      unless result.name == 'signal'
        session_resource.delete
        session_data['status'] = 'disconnected'
      end
    when 'connected'
      # Always send the url, client may not have received it last time, or navigated away
      log 'Sending demo page to mobile client'
      session_resource.post(
        JSON('url' => hostUri + 'api_button_demo.html'),
        { :content_type => :json }
      )
      # clients take finite time to receive and render the url, may want to delay the prompt for a short period.
      # use network quality value to determine how long a delay is needed.
      result = ask 'Please select one of the buttons. Button 3 will end this demo.', {
        :allowSignals => [ 'state_change', 'new_message' ],
        :choices => '[1 DIGIT]',
        :mode => 'dtmf',
        :attempts => 5,
        :timeout => 10.0,
        :onSignal => lambda do |signal|
          case signal.value
          when 'state_change'
            session_data = JSON(session_resource.get(:accept => :json).to_s)
            log 'Session respresentation: ' + session_data.inspect
          when 'new_message'
            msg_data = JSON(message_resource.get(:accept => :json).to_s)
            log 'Message respresentation: ' + msg_data.inspect
            say "You pressed #{msg_data['buttonName']}."
            if msg_data['buttonNumber'] == '2'
              say 'This button ends the demo.'
              session_resource.delete
              session_data['status'] = 'disconnected'
              next
            end
          end
        end
      }
      log "Connected ask result: name is #{result.name}, value is #{result.value}."
      unless result.name == 'signal'
        session_resource.delete
        session_data['status'] = 'disconnected'
      end
    when 'disconnected'
      say 'The ChoiceView server has ended the session.'
    else
      say 'Cannot communicate with the mobile device, try again later.'
      session_resource.delete
      session_data['status'] = 'disconnected'
    end
  end
else
  session_resource.delete if session_resource && session_data && session_data['status'] != 'disconnected' 
end

say 'The demo is ending now. Goodbye.'
hangup
