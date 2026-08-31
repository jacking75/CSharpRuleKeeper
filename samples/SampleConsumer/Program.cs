using System;
using System.Threading.Tasks;

namespace SampleConsumer;

static class Program
{
    static async Task Main()
    {
        await Task.Delay(TimeSpan.Zero);
        Console.WriteLine("CSharpRuleKeeper analyzer sample is active.");
    }
}
