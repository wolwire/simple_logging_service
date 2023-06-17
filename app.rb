require 'sinatra'
require 'json'
require 'fileutils'
require 'sqlite3'
require 'thread'

module LogFileOperations
  def self.setup_file_lock(file_path)
    @file_lock = Mutex.new
    @file_path = file_path
  end

  def self.write_to_file(data)
    @file_lock.synchronize do
      File.open(@file_path, 'a+') do |file|
        file.puts JSON.dump(data)
      end
    end
  end

  def self.truncate_file
    @file_lock.synchronize do
      File.truncate(@file_path, 0)
    end
  end

  def self.process_batch(db)
    batch_data = File.readlines(@file_path)
    batch_data.each do |line|
      data = JSON.parse(line)
      unix_ts = data['unix_ts']
      user_id = data['user_id']
      event_name = data['event_name']
      db.execute('INSERT INTO event_logs (unix_ts, user_id, event_name) VALUES (?, ?, ?)', [unix_ts, user_id, event_name])
    end
    truncate_file
  end
end

# Define the file path
file_path = 'log_data.txt'

# Define the maximum file size in bytes (10 MB)
max_file_size = 10 * 1024 * 1024

# Define the rotation interval in seconds
rotation_interval = 30

# Set up the database connection
db = SQLite3::Database.new('event_logs.db')

# Create a table if it doesn't exist
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS event_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    unix_ts INTEGER,
    user_id INTEGER,
    event_name TEXT
  );
SQL

# Set up file lock and operations
LogFileOperations.setup_file_lock(file_path)

# Define a POST endpoint for logging events
post '/log' do
  data = JSON.parse(request.body.read)
  unix_ts = data['unix_ts']
  user_id = data['user_id']
  event_name = data['event_name']
  LogFileOperations.write_to_file(data)

  file_size = File.file?(file_path) ? File.size(file_path) : 0
  if file_size > max_file_size
    LogFileOperations.process_batch(db)
  end

  status 200
  'Event logged successfully'.to_json
end

# Start a background thread for log rotation
Thread.new do
  loop do
    sleep(rotation_interval)

    file_size = File.size(file_path)
    if file_size > max_file_size
      LogFileOperations.process_batch(db)
    end
  end
end

# Start the server
set :bind, '0.0.0.0' # Bind to all network interfaces
set :port, 4567      # Set the port number

