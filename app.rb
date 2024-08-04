# app.rb
require 'sinatra'
require 'sinatra-websocket'
require 'sequel'
require 'json'

set :server, 'thin'
set :sockets, []

DB = Sequel.sqlite('chat.db')

DB.create_table? :users do
  primary_key :id
  String :username, unique: true, null: false
  String :password, null: false
end

DB.create_table? :messages do
  primary_key :id
  String :username, null: false
  String :message, null: false
  DateTime :timestamp, default: Sequel::CURRENT_TIMESTAMP
end

User = DB[:users]
Message = DB[:messages]

helpers do
  def authenticated?
    session[:user_id]
  end

  def current_user
    User.where(id: session[:user_id]).first
  end

  def login(username, password)
    user = User.where(username: username).first
    if user && user[:password] == password
      session[:user_id] = user[:id]
      true
    else
      false
    end
  end

  def logout
    session[:user_id] = nil
  end
end

enable :sessions

get '/' do
  if !request.websocket?
    erb :index
  else
    request.websocket do |ws|
      ws.onopen do
        settings.sockets << ws
      end

      ws.onmessage do |msg|
        message = JSON.parse(msg)
        Message.insert(username: message["username"], message: message["message"])
        EM.next_tick { settings.sockets.each{|s| s.send(msg) } }
      end

      ws.onclose do
        settings.sockets.delete(ws)
      end
    end
  end
end

post '/login' do
  if login(params[:username], params[:password])
    redirect '/'
  else
    "Login failed"
  end
end

post '/logout' do
  logout
  redirect '/'
end

post '/signup' do
  if params[:password] == params[:password_confirmation]
    begin
      User.insert(username: params[:username], password: params[:password])
      redirect '/'
    rescue Sequel::UniqueConstraintViolation
      "Username already taken"
    end
  else
    "Password confirmation doesn't match"
  end
end
