defmodule PouCon.TestMocks do
  Mox.defmock(PouCon.DataPointManagerMock, for: PouCon.Hardware.DataPointManagerBehaviour)
end
