require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'

require 'date'

BASE_URL = ENV['RACK_ENV'] == 'development' ? '' : '/timers'

configure do
  enable :sessions
  set :session_secret, 'this/is/a/s3cr3t/pw'
end

helpers do
  def button_label(index)
    if session[:timers][index][:timer_on]
      'Stop'
    else
      'Start'
    end
  end

  def timer
    timer_id = params[:timer_id].to_i
    session[:timers][timer_id] || halt(404)
  end

  def display_time_entry(entry)
    if entry[:stop].nil?
      "#{entry[:date].strftime('%d-%b-%y %H:%M:%S')} : on-going"
    else
      elapsed = elapsed_mins(entry[:start], entry[:stop])
      "#{entry[:date].strftime('%d-%b-%y %H:%M:%S')} : #{elapsed} mins"
    end
  end
end

before do
  session[:timers] ||= []
  pp ENV
end

get '/' do
  redirect url('/timers')
end

get '/timers' do
  if session[:timers].empty?
    session[:message] = "Click 'Add new timer' below to add some timers!"
  end

  @timers = session[:timers]
  erb :timers
end

get '/timers/new' do
  erb :new_timer
end

get '/timers/:timer_id' do
  @timer = timer
  erb :timer
end

post '/timers/new' do
  timer_name = params[:timer_name].strip
  session[:timers] << { name: timer_name, timer_on: false, entries: [] }
  redirect url('/timers')
end

post '/timers/:timer_id/action' do
  if timer[:timer_on]
    entry = timer[:entries].last[:stop] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timer[:timer_on] = false
    session[:message] = "Timer '#{timer[:name]}' ended"
  else
    timer[:entries] << { date: DateTime.now, start: Process.clock_gettime(Process::CLOCK_MONOTONIC), stop: nil }
    timer[:timer_on] = true
    session[:message] = "Timer '#{timer[:name]}' started"
  end
  redirect url('/timers')
end

get '/csv.txt' do
  headers['Content-Type'] = 'text/plain'
  csv_out(session[:timers])
end

# ======== Helper methods for CSV output ============

def csv_out(timers)
  arrays = entry_arrays(timers).sort_by { |ary| [ary[0], ary[2], ary[1]] }

  # convert entry arrays to strings for output
  arrays.map { |ary| ary.join(',') }.join("\n")
end

def entry_arrays(timers)
  entry_arrays = []
  timers.each do |timer|
    timer_name = timer[:name]
    entry_arrays += row_arrays(timer_name, timer[:entries])
  end
  entry_arrays
end

def row_arrays(timer_name, entries)
  rows = []
  entries.each do |entry|
    date = entry[:date].strftime('%d-%b-%y')
    start_time = entry[:date].strftime('%H:%M:%S')

    next if entry[:stop].nil?
    elapsed = elapsed_mins(entry[:start], entry[:stop])
    rows << [date,timer_name,start_time,calc_end_time(start_time, elapsed)]
  end
  rows
end

def elapsed_mins(start_s, stop_s)
  mins = (stop_s - start_s) / 60.0
  mins.round(2)
end

def calc_end_time(start_time, elapsed_mins)
  elapsed_s = (elapsed_mins * 60).round
  h, m, s = start_time.split(':').map(&:to_i)

  # calc new s and m
  s_new = s + elapsed_s
  m_new = m + s_new.divmod(60).first
  s_new = s_new.divmod(60).last

  # calc new h and m
  h_new = h + m_new.divmod(60).first
  m_new = m_new.divmod(60).last

  "#{sprintf("%02d",h_new)}:#{sprintf("%02d",m_new)}:#{sprintf("%02d",s_new)}"
end
