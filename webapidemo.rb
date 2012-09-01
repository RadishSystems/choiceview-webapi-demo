# webapidemo.rb
#
# ChoiceView is a Communications-as-a-Service (CAAS) platform that allows visual information
# to be sent from a contact center agent or IVR to mobile users equipped with the ChoiceView app.  
#
# Below is sample source code for an IVR script that enhances an existing IVR to become a
# ChoiceView-enabled visual IVR.  The resulting visual IVR can send visual menus to the caller,
# receive menu selections back from the caller, receive data entered by the caller and provide
# visual responses to the caller, in addition to providing standard voice prompts and DTMF.
#
# The sample script below illustrates use of ChoiceView for implementing a simple visual IVR demo.
# It's intended that the concepts and code provided herein can be used to create production visual
# IVR scripts.
#
# The ChoiceView app is available for free at the Apple App Store and Android Market.  Once it's
# installed on your mobile device, you can try the demo by calling 720-515-6994.
#
# Copyright © 2012 Radish Systems LLC
# All rights reserved.
# Learn more at www.radishsystems.com.
#
# Author: Darryl Jacobs <darryl@radishsystems.com>
#
# Tropo script showing how to use the ChoiceView IVR REST API to:
#
# 1. connect to a ChoiceView server
# 2. register to receive notifications when the connection state changes
# 3. send web pages to the client
# 4. receive control notifications from the client when the user presses a button on the web page
#
# How to run this script:
# Create a Tropo account, upload this script to the hosting area,
# then add a new scripting application that loads this script.
#
# The web page referred to by the script is at
# http://cvnet2.radishsystems.com/choiceview/ivr/api_button_demo.html
# View the source of this page to see how the button links are coded.
#
# Contact Radish Systems at www.radishsystems.com/support/contact-radish-customer-support/
# or support@radishsystems.com or darryl@radishsystems.com to get the information needed
# to access the ChoiceView REST API.

require 'rubygems'
require 'json'
require 'rest_client'

hostingUri = 'https://cvnet2.radishsystems.com/Choiceview/ivr/'
# Replace these values with the username and password must be provided by Radish Systems
username = 'USERNAME'
password = 'PASSWORD'

session_resource = nil
message_resource = nil
session_data = nil
actor = 'vanessa'

# Start the ChoiceView session
say('Welcome to the ChoiceView visual IVR demo from Radish Systems.', { :voice => actor })

signalUri = "https://api.tropo.com/1.0/sessions/#{$currentCall.sessionId}/signals?action=signal&value="

begin

# The POST request that starts the session must run in background
# while an ask command runs prompting the user to start the ChoiceView client
# and press the start button to establish the connection.
#
# The rest_client gem is used to make the REST API calls.
# More info on this gem is at http://github.com/archiloque/rest-client
#
# I'm sure there are Ruby Gems for doing asynchronous tasks, I'll update the code
# when I find one that works with Tropo.

Thread.abort_on_exception = true
postThread = Thread.new do
  log 'Sending POST request to start ChoiceView session'

  # The ChoiceView switch uses the mobile device phone number to connect the ChoiceView client
  # data connection on the device to the voice call on the IVR.

  RestClient.post "https://#{username}:#{password}@cvnet2.radishsystems.com/ivr/api/sessions",
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
        session_resource = RestClient::Resource.new(response.headers[:location], :user => username, :password => password)
        session_data = JSON response.to_s
        log 'Session resource: ' + session_resource.inspect
        log 'Session representation: ' + session_data.inspect
        msgUriIndex = session_data['links'].find_index { |link| link['rel'].end_with?('controlmessage') }
        message_resource = RestClient::Resource.new(session_data['links'][msgUriIndex]['href'], :user => username, :password => password) if msgUriIndex
        log 'Message resource: ' + message_resource.inspect
      else
        raise 'Cannot start session - status code: ' + response.code.to_s
      end
    end

  # This block will go away - signal should be sent by the API, not the Tropo script!
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

# While waiting for the response to the POST request,
# use an ask command to tell the user to start the ChoiceView session.
# When the user starts the session, a signal is sent to Tropo that interrupts the ask command. 
# If the user never starts a session, the request will time out either in the script or
# on the ChoiceView switch.

result = ask 'Stay on this call and return to the Home screen. Tap ChoiceView, then tap Start', {
  :voice => actor,
  :allowSignals => [ 'state_change' ],
  :choices => '[1 DIGIT]',
  :mode => 'dtmf',
  :attempts => 3,
  :timeout => 10.0
}

# wait here until POST thread ends
postThread.join

rescue Exception
  say('Cannot connect to the ChoiceView server at this time.  Please try again later.', { :voice => actor })
  log "Exception while connecting to ChoiceView switch: #{$!}"
  raise
end

# Send the button demo page to the mobile device,
# then loop until the user stops the demo or the session ends or times out.

unless session_data.nil?

  until session_data['status'] == 'disconnected'

    case session_data['status']
    when 'interrupted'
      # Status is set to interrupted when the data connection to the ChoiceView client is
      # temporarily unavailable.  This can happen if the mobile network connection fails,
      # or if the user switches to another application on his device.  The switch will notify
      # the script if the connection doesn't re-establish after a set period of time, or if
      # the client has shut down the connection manually, or has shut down the ChoiceView client.

      result = ask 'Waiting for the mobile device to reconnect.', {
        :voice => actor,
        :allowSignals => [ 'state_change' ],
        :choices => '[1 DIGIT]',
        :mode => 'dtmf',
        :attempts => 5,
        :timeout => 10.0,
        :onSignal => lambda do |signal|
          if signal.value == 'state_change'
            session_data = JSON(session_resource.get(:accept => :json).to_s)
            log 'Session representation: ' + session_data.inspect
            say('Device has reconnected...', { :voice => actor }) if session_data['status'] == 'connected'
          end
        end
      }
      log "Interrupted ask result: name is #{result.name}, value is #{result.value}."

      unless result.name == 'signal'
        session_resource.delete
        session_data['status'] = 'disconnected'
      end

    when 'connected'
      # Always send the url before starting the voice prompt.
      # The client may not have received the url the last time,
      # or may have accessed a previously viewed page in the ChoiceView client.

      log 'Sending demo page to mobile client'
      session_resource.post(
        JSON('url' => hostingUri + 'api_button_demo.html'),
        { :content_type => :json }
      )

      # (Advanced technique not in this version of the demo)
      # ChoiceView clients can take several seconds to receive and render the url.
      # Scripts may want to delay starting the voice prompt for a short period of time
      # to keep the prompt in sync with the client display.
      # You can use the network quality value in the session representation
      # to determine how long a delay is needed.

      result = ask 'Please select one of the buttons. Button 3 will end this demo.', {
        :voice => actor,
        :allowSignals => [ 'state_change', 'new_message' ],
        :choices => '[1 DIGIT]',
        :mode => 'dtmf',
        :attempts => 5,
        :timeout => 10.0,
        :onSignal => lambda do |signal|
          case signal.value
          when 'state_change'
            session_data = JSON(session_resource.get(:accept => :json).to_s)
            log 'Session representation: ' + session_data.inspect
          when 'new_message'
            msg_data = JSON(message_resource.get(:accept => :json).to_s)
            log 'Message representation: ' + msg_data.inspect
            say("You pressed #{msg_data['buttonName']}.", { :voice => actor })
            if msg_data['buttonNumber'] == '2'
              say('This button ends the demo.', { :voice => actor })
              session_resource.delete
              session_data['status'] = 'disconnected'
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
      # The user or the switch ended the session on the mobile device
      say('The ChoiceView server has ended the session.', { :voice => actor })

    else
      # Should never see these states after the connection has been established.
      say('Cannot communicate with the mobile device, try again later.', { :voice => actor })
      session_resource.delete
      session_data['status'] = 'disconnected'
    end
  end
  log '----- Session ended -----'
else
  session_resource.delete unless session_resource.nil?
end

say('Thank you for using ChoiceView. Goodbye.', { :voice => actor })
