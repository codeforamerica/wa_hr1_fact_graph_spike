# frozen_string_literal: true

require "open3"

# The command's side of the JSON protocol (ADR-0003 in samesite2026-app-02).
RSpec.describe "exe/wa-hr1-evaluate" do
  EXE = File.expand_path("../exe/wa-hr1-evaluate", __dir__)

  def run(stdin, *args) = Open3.capture3(RbConfig.ruby, EXE, "--compact", *args, stdin_data: stdin)

  it "writes exactly one JSON object to stdout, with the protocol version" do
    stdout, stderr, status = run('{"renewer": {"renewal_month": "2027-03", "age": 65}}')
    expect(status.exitstatus).to eq 0
    expect(stderr).to be_empty
    expect(stdout.lines.size).to eq 1
    output = JSON.parse(stdout)
    expect(output).to include("protocol_version" => WaHr1::PROTOCOL_VERSION, "likely_eligible" => false)
  end

  it "exits 1 with nothing on stdout, and doesn't echo the input, when the input isn't JSON" do
    stdout, stderr, status = run('{"renewer": {"name": "Maya Secret"')
    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).not_to include("Maya Secret")
  end

  it "exits 1 when the input isn't a JSON object" do
    stdout, _stderr, status = run("[]")
    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
  end

  it "exits 1 for an unknown option" do
    _stdout, _stderr, status = run("{}", "--nope")
    expect(status.exitstatus).to eq 1
  end
end
