module ActiveShipping
  class BLR < Carrier
    self.retry_safe = true

    cattr_reader :name
    @@name = "BLR"

    SERVICE_TYPES = {
      "1" => "רגיל",
      "2" => "דחוף",
      "3" => "בהול",
      "11" => "רגיל כפול",
      "21" => "דחוף כפול",
      "31" => "בהול כפול",
    }

    DROPOFF_TYPES = {
      "regular_pickup"  => "1",
      "collect"         => "2",
      "transfer"        => "3",
    }

    VEHICLE_TYPES = {
      "bike"  => "1",
      "car"   => "2",
    }

    ERROR_CODES = {
      "-200" => "אירעה שגיאה בסוג משלוח",
      "-201" => "אירעה שגיאה ברחוב מוצא",
      "-202" => "אירעה שגיאה במס' בית מוצא",
      "-203" => "אירעה שגיאה בעיר מוצא",
      "-204" => "אירעה שגיאה ברחוב יעד",
      "-205" => "אירעה שגיאה במס' בית יעד",
      "-206" => "אירעה שגיאה בעיר יעד",
      "-207" => "אירעה שגיאה בשם חברה במוצא",
      "-208" => "אירעה שגיאה בשם חברה ביעד",
      "-209" => "אירעה שגיאה בהוראות למשלוח",
      "-210" => "אירעה שגיאה בדחיפות",
      "-211" => "אירעה שגיאה בשדה 12",
      "-212" => "אירעה שגיאה בסוג דיוור",
      "-213" => "אירעה שגיאה במס' חבילות",
      "-214" => "אירעה שגיאה בהאם כפול?",
      "-215" => "אירעה שגיאה בשדה 16",
      "-216" => "אירעה שגיאה במס’ הזמנה אצלכם",
      "-217" => "אירעה שגיאה בקוד לקוח בבלדר",
      "-218" => "אירעה שגיאה בשדה 19",
      "-219" => "אירעה שגיאה בהערות נוספות",
      "-220" => "אירעה שגיאה במס' משטחים",
      "-221" => "אירעה שגיאה בקוד עיר מוצא",
      "-222" => "אירעה שגיאה בקוד עיר יעד",
      "-223" => "אירעה שגיאה בשם איש קשר",
      "-224" => "אירעה שגיאה בטלפון איש קשר",
      "-225" => "אירעה שגיאה באימייל",
      "-226" => "אירעה שגיאה בתאריך ביצוע",
      "-227" => "אירעה שגיאה בגוביינא",
      "-100" => "חשבון לא קיים",
      "-999" => "איראה שגיאה לא ידועה"
    }
    
    def requirements
      [:password, :account, :login]
    end

    def find_rates(origin, destination, packages, options = {})
      options = @options.merge(options)
      packages = Array(packages)
      rate_estimates = []
      success = true
      message = nil
      

      biz = Biz::Schedule.new do |config|
        config.hours      = options[:biz][:hours].each{|k,v| v.stringify_keys!}
        config.holidays   = options[:biz][:holidays]
        config.time_zone  = options[:biz][:time_zone]
      end

      area = options[:biz][:areas].select do |area| 
        area[:level_en].repeated_permutation(2).select{|x,y| [x,y]==[origin.city,destination.city]}.any? ||
        area[:level_he].repeated_permutation(2).select{|x,y| [x,y]==[origin.city,destination.city]}.any?
      end.try(:first)

      if area
        time_now = Time.now.utc # Time.local(2017, 6, 14, 13,1).utc
        biz_hours = biz.in_hours?(time_now)

        services = biz_hours ? 
          options[:biz][:services].select{|service| service[:active_until].nil? || time_now < ActiveSupport::TimeZone[options[:biz][:time_zone]].parse(service[:active_until]).utc } : 
          options[:biz][:services]

        services.each do |service|

          logger.info "-"*100
          logger.info options[:biz][:time_zone]
          logger.info ActiveSupport::TimeZone[options[:biz][:time_zone]]
          logger.info time_now
          logger.info service[:time_to_deliver]
          logger.info service[:time_to_deliver].to_i*60
          logger.info (time_now + service[:time_to_deliver].to_i*60).to_s
          logger.info ActiveSupport::TimeZone[options[:biz][:time_zone]].parse((time_now + service[:time_to_deliver].to_i*60).to_s)


          

          rate_estimates << RateEstimate.new(origin, destination, @@name,
                              SERVICE_TYPES[service[:service_code].to_s], :service_code => service[:service_code].to_s,
                              :total_price => (area[:amount] * service[:weight]), :currency => 'ILS', :packages => packages,
                              :pickup_time => 
                                [ 
                                  (
                                    biz_hours ? 
                                      ActiveSupport::TimeZone[options[:biz][:time_zone]].parse((time_now + service[:time_to_deliver].to_i*60).to_s) :
                                      biz.time(service[:time_to_deliver], :minutes).after(time_now)
                                  ).to_s
                                ]
                              )
        end
      end

      RateResponse.new(success, message, {}, :rates => rate_estimates, :xml => "response", :request => "last_request", :log_xml => options[:log_xml])
      # rate_request = build_rate_request(origin, destination, packages, options)
      # xml = commit(save_request(rate_request), (options[:test] || false))
      # xml = ""
      # parse_rate_response(origin, destination, packages, xml, options)
    end

    # Get Shipping labels
    def create_shipment(origin, destination, packages, options = {})
      options = @options.merge(options)
      packages = Array(packages)
      raise Error, "Multiple packages are not supported yet." if packages.length > 1

      request = build_shipment_request(origin, destination, packages, options)

      logger.debug(request) if logger
      response = commit(save_request(request), options)
      parse_ship_response(response)
    end


    protected

    def build_shipment_request(origin, destination, packages, options = {})
      pParams = [ options[:dropoff_type] || 1, 
                  origin.address1,      origin.address2,      origin.city,
                  destination.address1, destination.address2, destination.city,
                  origin.company, destination.company,
                  options[:comments],
                  options[:service_code],
                  0, # N/A
                  options[:vehicle_type] || 1,
                  packages.size,
                  options[:dual_shipping].nil? ? 1 : 2, # dual shipping - to deliver a package and get another to the sender
                  0, # N/A
                  options[:order_id],
                  options[:account],
                  0, # N/A
                  options[:extra_comments],
                  options[:pallet_number] || 0,
                  nil, # origin city by id in databases - Not Mandatory
                  nil, # destination city by id in databases - Not Mandatory
                  origin.name,
                  origin.phone,
                  options[:email],
                  options[:pickup_date], # .to_time.strftime("%F") if options[:pickup_date],  # yyyy-mm-dd
                  options[:collection_payment] || 0, 
                ].map{|p|  p.is_a?(String) ? p.gsub(/;/,"") : p}.join(";").gsub(/("|״)/,"'")

      xml_builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml['soap'].Envelope( 'xmlns:soap' => 'http://schemas.xmlsoap.org/soap/envelope/',
                              'xmlns:xsi'  => 'http://www.w3.org/2001/XMLSchema-instance',
                              'xmlns:xsd'  => 'http://www.w3.org/2001/XMLSchema') do
          xml['soap'].Body do
            xml.SaveData(xmlns: 'http://tempuri.org/') do
              xml.pParam(pParams)
            end
          end
        end
      end
      xml_builder.to_xml
    end



    def parse_ship_response(response)
      xml = build_document(response, 'Envelope')
      success = response_success?(xml)
      message = response_message(xml)
      raise ActiveShipping::ResponseContentError, StandardError.new(message) unless success
      
      response_info = Hash.from_xml(response)
      tracking_number =  xml.at('SaveDataResult').text
      labels = [Label.new(tracking_number, nil)]
      LabelResponse.new(success, message, response_info, {labels: labels})
    end

    def response_success?(document)
      result = document.at('SaveDataResult')
      return !result.nil? && !ERROR_CODES.include?(result.text)
    end

    def response_message(document)
      result = document.at('SaveDataResult')
      ERROR_CODES.include?(result.try(:text)) ? "#{ERROR_CODES[result.text]} (#{result.text})" : nil
    end

    def commit(request, options)
      ssl_post(options[:endpoint], request.gsub("\n", ''),'Content-Type' => 'text/xml; charset=utf-8')
    end


    def build_document(xml, expected_root_tag)
      document = Nokogiri.XML(xml) { |config| config.strict }
      document.remove_namespaces!
      if document.root.nil? || document.root.name != expected_root_tag
        raise ActiveShipping::ResponseContentError.new(StandardError.new('Invalid document'), xml)
      end
      document
    rescue Nokogiri::XML::SyntaxError => e
      raise ActiveShipping::ResponseContentError.new(e, xml)
    end

    def location_uses_imperial(location)
      %w(US LR MM).include?(location.country_code(:alpha2))
    end
  end
end
