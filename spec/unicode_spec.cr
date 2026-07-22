require "./spec_helper"

describe "Unicode structural keys" do
  it "decodes Unicode keys in tabular headers" do
    Toon.decode("items[1]{名前,age}:\n  Ada,30").should eq({
      "items" => [
        {"名前" => "Ada", "age" => 30_i64} of String => Toon::JsonValue,
      ] of Toon::JsonValue,
    } of String => Toon::JsonValue)
  end

  it "decodes Unicode keys in nested field groups" do
    Toon.decode("items[1]{id,顧客{名前,国}}:\n  1,Ada,DK").should eq({
      "items" => [
        {
          "id" => 1_i64,
          "顧客" => {"名前" => "Ada", "国" => "DK"} of String => Toon::JsonValue,
        } of String => Toon::JsonValue,
      ] of Toon::JsonValue,
    } of String => Toon::JsonValue)
  end

  it "round-trips Unicode keyed tabular objects" do
    value = {
      "東京" => {"人口" => 14_i64, "国" => "日本"} of String => Toon::JsonValue,
      "京都" => {"人口" => 1_i64, "国" => "日本"} of String => Toon::JsonValue,
    } of String => Toon::JsonValue

    Toon.decode(Toon.encode(value)).should eq(value)
  end
end
