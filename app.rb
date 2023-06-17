require 'sinatra'
require 'json'
require 'fileutils'
require 'pg'
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
      insert_query = <<-SQL
        INSERT INTO event_logs (unix_ts, user_id, event_name)
        VALUES ($1, $2, $3)
      SQL

      db.exec_params(insert_query, [unix_ts, user_id, event_name])
    end
    truncate_file
  end
end

# Define the file path
file_path = 'log_data.txt'


max_file_size = 10 * 1024

rotation_interval = 30

db = PG.connect(host: ENV['POSTGRES_HOST'], dbname: ENV['POSTGRES_DB'], user: ENV['POSTGRES_USER'], password: ENV['POSTGRES_PASSWORD'])

# Create a table if it doesn't exist
create_table_query = <<-SQL
  CREATE TABLE IF NOT EXISTS event_logs (
    id SERIAL PRIMARY KEY,
    unix_ts INTEGER,
    user_id INTEGER,
    event_name TEXT
  );
SQL

db.exec_params(create_table_query)

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
set :bind, ENV['HOST'] # Bind to all network interfaces
set :port, ENV['PORT']      # Set the port number

