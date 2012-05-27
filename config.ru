require File.join( File.dirname( __FILE__ ), "maru/master" )

use Rack::CommonLogger
run Maru::Master
