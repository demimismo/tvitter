require 'rubygems'
require 'twitter'
require 'lib/daemon.rb'
require_gem 'log4r'
require_gem 'feedtools'
require_gem 'activerecord'
include Log4r

ActiveRecord::Base.establish_connection(
  :adapter  => "mysql",
  :username => "root",
  :host     => "localhost",
  :password => "",
  :database => "tvitter" 
)

TVITTER_CONFIG = {
  :user =>      "tvitter",    # nombre de usuario de twitter con el que se realizan los envíos
  :pass =>      "telemola",   # contraseña de twitter
  :interval =>  10.minutes,   # intervalo de actualización
  :snooze =>    23,           # hora de irse a la cama
  :wake_up =>   9,            # hora de levantarse
  :debug =>     true          # modo debug (no envía a twitter)
}

class Channel < ActiveRecord::Base
end

class Tvitter < Daemon::Base
  def self.start
    @log = Log4r::Logger.new 'tvitter'
    file_logger = Log4r::FileOutputter.new('messages_log',
                        :filename => "../log/messages.log",
                        :trunc => false,
			:formatter => PatternFormatter.new(:pattern => "[%l] %d :: %m"))
    @log.outputters = file_logger
    @log.info 'Sesión iniciada'
    @snooze = false
    @threads = []
    @mutex = Mutex.new

    # bucle de ejecución del demonio
    loop do 

      wake_up if @snooze

      channels = Channel.find(:all)

      # comienza agregación (supuestamente) multi-hilo
      @log.info "Comenzando agregación, " + channels.length.to_s + " canales en base de datos"
      channels.each do |channel|
	begin
	  @threads << Thread.new(channel) { |channel| update(channel) }
	rescue Exception
	  @log.error $!
	end
      end

      @threads.each { |thread| thread.join }
      @threads = []
      if Time.now.hour > TVITTER_CONFIG[:snooze]
        #to_bed
      else
        @log.info "Esperando hasta fin de intervalo"
        sleep TVITTER_CONFIG[:interval]
      end
    end
  end

  def self.update(channel)
    begin
    url = ""
    @mutex.synchronize { url = channel.url }
    feed = fetch_channel url
    current_show = current_show(feed) unless feed.items.nil?
    unless current_show[:title].empty? || current_show[:title] == channel.last
      @log.info "Enviando a twitter: "+ channel.name + " - " + current_show[:title]
      channel.last = current_show[:title]
      @mutex.synchronize { channel.save }
      begin
	Twitter::Base.new(TVITTER_CONFIG[:user], TVITTER_CONFIG[:pass]).update('Próximo programa en ' + channel.name + ': ' + current_show[:title])
      rescue NoMethodError
      end
    else
      @log.info "No modificado: "+ channel.name + " - " + current_show[:title]
    end
    rescue Exception
      @log.error $!
    end
  end

  def self.stop
    @log.info 'Sesión finalizada'
  end

  def self.wake_up
    @snooze = false
    @log.info "Me levanto"
    twitter_send "Buenos días"
  end

  def self.to_bed
    @snooze = true
    @log.info "Me voy a dormir"
    twitter_send "Buenas noches :-)"
    sleep 10.hours
  end


  def self.twitter_send(msg)
    Twitter::Base.new(TVITTER_CONFIG[:user], TVITTER_CONFIG[:pass]).update(msg) unless TVITTER_CONFIG[:debug]
    @log.info "Enviando a twitter: " + msg
  end


  # retorna el feed parseado por feed_tools
  def self.fetch_channel(url)
    FeedTools::Feed.open(url)
  end

  # obtiene el programa actual del feed especificado
  # este método guarrea el feed para obtener la fecha y hora del programa,
  # por lo que es dependiente de la estructura de dicho feed
  def self.current_show(feed)
    current_show = { :title => "", :delta => -1800 }
    
    feed.items.each do |item|
      match = /(.*) - .* (\d?\d)-(\d\d) (\d?\d):(\d?\d)/.match(item.title)
      @log.debug "Regexp error: " + item.title if match.nil?
      next if match.nil?

      title = match[1]
      dia = match[2].to_i
      mes = match[3].to_i
      hora = match[4].to_i
      minuto = match[5].to_i

      title += " (#{hora}:#{minuto})"
      title += " #{item.link}" unless item.link.nil?

      ahora = Time.now
      delta = ahora - Time.local(ahora.year, mes, dia, hora, minuto, 0)
      # guardamos el más cercano en el tiempo
      current_show = { :title => title, :delta => delta } if delta < 0 && delta > current_show[:delta]
    end
    return current_show
  end

end

Tvitter.daemonize
#Tvitter.start
