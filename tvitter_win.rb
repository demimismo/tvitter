require 'rubygems'
require "twitter"
require 'log4r'
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
  :snooze =>    22,           # hora de irse a la cama
  :wake_up =>   9,            # hora de levantarse
  :debug =>     false,        # modo debug (no envía a twitter)
}

class Channel < ActiveRecord::Base
end

class Tvitter
  def initialize
    @log = Logger.new 'tvitter'
#    file = FileOutputter.new 'fileOutputter', :filename => "log/tvitter.log", :trunc => false
#    file.formatter = PatternFormatter.new(:pattern => "[%l] %d :: %m")
#    @log.add file
    @log.info 'Sesión iniciada'
    @snooze = false

    # bucle de ejecución del demonio
    loop do 

      wake_up if @snooze

      channels = Channel.find :all
      @log.info "Comenzando agregación, " + channels.length.to_s + " canales en base de datos"
      channels.each do |channel|
        current_show = current_show(fetch_channel(channel.url))
        unless current_show[:title].empty? || current_show[:title] == channel.last
          channel.last = current_show[:title]
          channel.save
          begin
            twitter_send 'Próximo programa en ' + channel.name + ': ' + current_show[:title]
          rescue NoMethodError
          end
        else
          @log.info "No modificado: "+ channel.name + " - " + current_show[:title]
        end
      end
      
      if Time.now.hour > TVITTER_CONFIG[:snooze]
        to_bed
        sleep 10.hours
      else
        @log.info "Esperando hasta fin de intervalo"
        sleep TVITTER_CONFIG[:interval]
      end
    end
    @log.info 'Sesión finalizada'
  end

  def wake_up
    @snooze = false
    @log.info "Me levanto"
    twitter_send "Buenos días"
  end

  def to_bed
    @snooze = true
    @log.info "Me voy a dormir"
    twitter_send "Buenas noches :-)"
  end


  def twitter_send(msg)
    Twitter::Base.new(TVITTER_CONFIG[:user], TVITTER_CONFIG[:pass]).update(msg) unless TVITTER_CONFIG[:debug]
    @log.info "Enviando a twitter: " + msg
  end

  # retorna el feed parseado pro feed_tools
  def fetch_channel(url)
    FeedTools::Feed.open(url)
  end

  # obtiene el programa actual del feed especificado
  # este método guarrea el feed para obtener la fecha y hora del programa,
  # por lo que es dependiente de la estructura de dicho feed
  def current_show(feed)
    current_show = { :title => "", :delta => -60000 }
    feed.items.each do |item|

      match = /(.*) - .*  (\d?\d)-(\d\d) (\d?\d):(\d?\d)/.match(item.title)
      title = match[1]
      dia = match[2].to_i
      mes = match[3].to_i
      hora = match[4].to_i
      minuto = match[5].to_i

      ahora = Time.now
      delta = ahora - Time.local(ahora.year, mes, dia, hora, minuto, 0)
      # guardamos el más cercano en el tiempo
      current_show = { :title => title, :delta => delta } if delta < 0 && delta > current_show[:delta]
    end
    return current_show
  end



end

Tvitter.new
