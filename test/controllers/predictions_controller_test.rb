require "test_helper"

class PredictionsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get predictions_index_url
    assert_response :success
  end

  test "should get predict" do
    get predictions_predict_url
    assert_response :success
  end

  test "should get show" do
    get predictions_show_url
    assert_response :success
  end
end
