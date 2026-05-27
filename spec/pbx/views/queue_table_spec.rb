# frozen_string_literal: true

RSpec.describe Pbx::Views::QueueTable do
  def make_queue(name: "supporto", **overrides)
    Pbx::CallQueue.new(
      name: name, strategy: "ringall", calls_waiting: 2,
      completed: 50, abandoned: 3, holdtime: 90,
      members: {},
      **overrides
    )
  end

  def make_member(**overrides)
    Pbx::QueueMember.new(
      queue: "supporto", name: "Alice", interface: "SIP/201",
      status: "not_in_use", paused: false,
      **overrides
    )
  end

  describe ".render" do
    context "with no queues" do
      it "returns the empty placeholder string" do
        output = described_class.render({}, 80, 5)
        expect(output).to be_a(String)
        expect(output).to include("No queues")
      end
    end

    context "with queues" do
      let(:queues) do
        {
          "supporto" => make_queue(name: "supporto"),
          "vendite" => make_queue(name: "vendite", calls_waiting: 0, completed: 10)
        }
      end

      it "returns a String" do
        expect(described_class.render(queues, 80, 5)).to be_a(String)
      end

      it "includes each queue name" do
        output = described_class.render(queues, 80, 5)
        expect(output).to include("supporto")
        expect(output).to include("vendite")
      end

      it "includes the queue count in the title" do
        output = described_class.render(queues, 80, 5)
        expect(output).to include("Queues (2)")
      end
    end
  end

  describe ".build" do
    it "reflects available/total agent counts" do
      available_member = make_member(status: "not_in_use", paused: false)
      busy_member = make_member(interface: "SIP/202", status: "in_use", paused: false)
      paused_member = make_member(interface: "SIP/203", status: "not_in_use", paused: true)

      members = {
        "SIP/201" => available_member,
        "SIP/202" => busy_member,
        "SIP/203" => paused_member
      }
      q = make_queue(members: members)
      table = described_class.build({"supporto" => q}, 5)
      expect(table.view).to include("1/3")
    end
  end

  describe ".format_holdtime" do
    it "returns — for zero" do
      expect(described_class.format_holdtime(0)).to eq("—")
    end

    it "returns — for nil" do
      expect(described_class.format_holdtime(nil)).to eq("—")
    end

    it "formats seconds into Xm YYs" do
      expect(described_class.format_holdtime(90)).to eq("1m 30s")
    end

    it "formats under one minute" do
      expect(described_class.format_holdtime(45)).to eq("0m 45s")
    end
  end
end
