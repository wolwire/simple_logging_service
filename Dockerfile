FROM ruby:latest

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY app.rb .

CMD ["bundle", "exec", "ruby", "app.rb"]
