require 'test_helper'

class RemoteBLRTest < ActiveSupport::TestCase
  include ActiveShipping::Test::Credentials
  include ActiveShipping::Test::Fixtures
  include HolidayHelpers

  def setup
    @options = credentials(:blr).merge(:test => true)
    @carrier = BLR.new(@options)
  rescue NoCredentialsFound => e
    skip(e.message)
  end

  def test_us_addresses_not_supported
    e = assert_raises ActiveShipping::ResponseContentError do
          @carrier.create_shipment(
            location_fixtures[:beverly_hills],
            location_fixtures[:new_york_with_name],
            package_fixtures.values_at(:chocolate_stuff),
            {
             :service_code => '1',
             :pickup_date => Time.now.to_time.strftime("%F"),
             :test=>true
            }      
          )
        end
    assert_equal(e.message, "איראה שגיאה לא ידועה (-999)")
  end

  def test_missing_service_code
    e = assert_raises ActiveShipping::ResponseContentError do
          @carrier.create_shipment(
            location_fixtures[:telaviv],
            location_fixtures[:ramatgan],
            package_fixtures.values_at(:chocolate_stuff),
            {
             :service_code => '',
             :pickup_date => Time.now.to_time.strftime("%F"),
             :test=>true
            }      
          )
        end
    assert_equal(e.message, "אירעה שגיאה בדחיפות (-210)")
  end

  def test_missing_location_values
    # origin_missing_parameters =     {city: "-203",name: "-223",address1: "-201",address2: "-202",phone: "-224"}
    # destination_missing_parameters = {city: "-206",address1: "-204",address2: "-206"}
    origin_missing_parameters =     {name: "-999"}
    origin_missing_parameters.each do |missing_parameter, error_code|
      e = assert_raises ActiveShipping::ResponseContentError do
            @carrier.create_shipment(
              Location.new(location_fixtures[:telaviv].to_hash.except(missing_parameter)),
              location_fixtures[:ramatgan],
              package_fixtures.values_at(:chocolate_stuff),
              {
               :service_code => '1',
               :pickup_date => Time.now.to_time.strftime("%F"),
               :test=>true
              }      
            )
          end
        assert e.message.include? error_code
    end
  end

  def test_missing_mandatory_options
    mandatory_options = {account: "-999",  pickup_date: "-226", dropoff_type: "-200", vehicle_type: "-212"}
    mandatory_options.each do |option, error_code|
      e = assert_raises ActiveShipping::ResponseContentError do
            @carrier.create_shipment(
              location_fixtures[:telaviv],
              location_fixtures[:ramatgan],
              package_fixtures.values_at(:chocolate_stuff),
              {
               :service_code => '1',
               :pickup_date => Time.now.to_time.strftime("%F"),
               :test=>true,
               option => '' 
              }      
            )
          end
      assert e.message.include? error_code
    end
  end

  def test_obtain_shipping_label
    response = @carrier.create_shipment(
      location_fixtures[:telaviv],
      location_fixtures[:ramatgan],
      package_fixtures.values_at(:chocolate_stuff),
      {
       :service_code => '1',
       :pickup_date => Time.now.to_time.strftime("%F"),
       :test=>true
      }      
    )

    assert response.success?
    assert_instance_of ActiveShipping::LabelResponse, response
  end

  def test_rates
    response = @carrier.find_rates(
      location_fixtures[:telaviv],
      location_fixtures[:ramatgan],
      package_fixtures.values_at(:wii)
    )

    assert_instance_of Array, response.rates
    assert response.rates.length > 0
    response.rates.each do |rate|
      assert_instance_of String, rate.service_name
      assert_kind_of Integer, rate.price
    end
  end

end
