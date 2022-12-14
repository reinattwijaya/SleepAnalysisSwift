//
//  ContentView.swift
//  SleepAnalysis
//
//  Created by Reinatt Wijaya on 2022/11/02.
//

import SwiftUI
import Charts

struct LineData: Encodable, Identifiable{
    let id = UUID()
    var Category: String
    var x: Date
    var y: Double
    
    init(Category:String, x: Date, y: Double){
        self.Category = Category
        self.x = x
        self.y = y
    }
}

public func formatDate(offset: Double)->Date{
    let date = Date.now.addingTimeInterval(offset)
//    let dateFormatter = DateFormatter()
//    let stringVal = dateFormatter.string(from: date)
    return date
}

struct ContentView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    
    @State var AwarenessData = [LineData](repeating: LineData(Category: "Awareness", x: formatDate(offset: 0.0), y: 0.0), count: 12*24*2)
    @State var SleepData = [LineData](repeating: LineData(Category: "Sleep", x: formatDate(offset: 0.0), y: 0.0), count: 12*24*2)
    @State var SleepSuggestionData = [LineData](repeating: LineData(Category: "Sleep Suggestion", x: formatDate(offset: 0.0), y: 0.0), count: 12*24*2)
    
    @AppStorage("sleep_onset") var sleep_onset: Date = Date.now
    @AppStorage("work_onset") var work_onset: Date = Date.now
    @AppStorage("work_offset") var work_offset: Date = Date.now
    
    @AppStorage("V0_x") var V0_x: Double = -0.8283
    @AppStorage("V0_y") var V0_y: Double = 0.8413
    @AppStorage("V0_n") var V0_n: Double = 0.6758
    @AppStorage("V0_H") var V0_H: Double = 13.3336
    
    @FetchRequest(sortDescriptors: []) var entries: FetchedResults<Entry>
    @FetchRequest(sortDescriptors: []) var V0_cores: FetchedResults<V0_main>
    
    
    var body: some View {
        GeometryReader{ geometry in
            VStack {
                Text("Sleep App")
                //                List{
                Chart {
                    ForEach(SleepData){
                        LineMark(
                            x: .value("x1", $0.x),
                            y: .value("y1", $0.y),
                            series: .value("sleep", "s")
                        ).foregroundStyle(by: .value("Category", $0.Category))
                        AreaMark(
                            x: .value("x1", $0.x),
                            y: .value("y1", $0.y)
                        ).foregroundStyle(.blue)
                    }
                    ForEach(AwarenessData){
                        LineMark(
                            x: .value("x", $0.x),
                            y: .value("y", $0.y),
                            series: .value("awareness", "a")
                        ).interpolationMethod(.catmullRom)
                            .foregroundStyle(by: .value("Category", $0.Category))
                    }
                    
                }.frame(height: geometry.size.height/3)
                //                }.refreshable {
                //                    print("something")
                //                }
                Chart(SleepSuggestionData) {
                    LineMark(
                        x: .value("x", $0.x),
                        y: .value("y", $0.y)
                    ).foregroundStyle(by: .value("Category", $0.Category))
                    AreaMark(
                        x: .value("x", $0.x),
                        y: .value("y", $0.y)
                    ).foregroundStyle(by: .value("Category", $0.Category))
                }.frame(height: geometry.size.height/3)
            }
            .padding()
            .onAppear{
                let startDate = Date.now.addingTimeInterval(-1.0*60*60*24*2)
                let V0 =  [-0.8590, -0.6837, 0.1140, 14.2133] //initial condition
                var sleep_pattern = [Double](repeating: 0.0, count: 12*24*2)
                for entry in entries{
                    if entry.sleepStart! < startDate{
//                        print(entry.sleepStart!)
                        continue
                    }else{
                        //distance from startDate:
                        let startToSleep = entry.sleepStart?.timeIntervalSince(startDate)
                        let sleepToSleep = entry.sleepEnd!.timeIntervalSince(entry.sleepStart!)
                        
                        //                        print(String(startToSleep!), String(sleepToSleep))
                        //fill out the array
                        let idx = Int(startToSleep!/60/5)
                        let offset = Int(sleepToSleep/60/5)
                        
//                        print(idx, offset)
                        
                        for i in 0..<offset{
                            sleep_pattern[idx+i] = 1.0
                        }
                    }
                }
                let y_data = pcr_simulation(V0: V0, sleep_pattern: sleep_pattern, step: 5/60.0)
//                let start = DispatchTime.now()
                var now = Date.now
                for x in 0...575{
                    let V0_core = V0_main(context: managedObjectContext)
                    V0_core.time = now.addingTimeInterval(Double(x)*5.0*60.0)
                    V0_core.y = y_data[x][0]
                    V0_core.x = y_data[x][1]
                    V0_core.n = y_data[x][2]
                    V0_core.h = y_data[x][3]
                    do {
                        try managedObjectContext.save()
                    } catch {
                        // handle the Core Data error
                    }
                }
//                let end = DispatchTime.now()
//                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
//                let timeInterval = Double(nanoTime) / 1_000_000_000
//                print("NANO TIME", timeInterval)
                for x in 0...575{
                    let C = 3.37*0.5*(1+coef_y*y_data[x][1] + coef_x * y_data[x][0])
                    let D_up = (2.46+10.2+C) //sleep thres
                    let awareness = D_up - y_data[x][3]
                    AwarenessData[x] = LineData(Category:"Alertness",x:formatDate(offset: Double(x)*5.0*60.0-1.0*60*60*24*2), y:Double(awareness))
                    SleepData[x] = LineData(Category:"Sleep",x:formatDate(offset: Double(x)*5.0*60.0-1.0*60*60*24*2), y:Double(sleep_pattern[x]))
                }
                //Sleep Suggestion
                var suggestion_pattern = [(Double, String)](repeating: (0.0, "Main Sleep"), count: 12*24*2)
                let step = 1/12.0
                let V0_suggest = [V0_x, V0_y, V0_n, V0_H]
                let suggest = Sleep_pattern_suggestion(V0: V0_suggest, sleep_onset: Int(sleep_onset.timeIntervalSince(Date.now)/60/5), work_onset: Int(work_onset.timeIntervalSince(Date.now)/60/5), work_offset: Int(work_offset.timeIntervalSince(Date.now)/60/5), step: step)
                let MainSleep = suggest.CSS
                let NapSleep = suggest.Nap

                //debug
                print("Main sleep: ", Date.now.addingTimeInterval(Double(MainSleep[0])*5.0*60.0).formatted(date: .numeric, time: .shortened))
                print("Main sleep: ", Date.now.addingTimeInterval(Double(MainSleep[1])*5.0*60.0).formatted(date: .numeric, time: .shortened))
                print("Nap sleep: ", Date.now.addingTimeInterval(Double(NapSleep[0])*5.0*60.0).formatted(date: .numeric, time: .shortened))
                print("Nap sleep: ", Date.now.addingTimeInterval(Double(NapSleep[1])*5.0*60.0).formatted(date: .numeric, time: .shortened))


                var idx = Int(MainSleep[0])
                var offset = Int(MainSleep[1])
                for i in 0..<offset{
                    suggestion_pattern[idx+i] = (1.0, "Main Sleep")
                }

                idx = Int(NapSleep[0])
                offset = Int(NapSleep[1])
                for i in 0..<offset{
                    suggestion_pattern[idx+i] = (1.0, "Nap")
                }

                for x in 0...575{
                    SleepSuggestionData[x] = LineData(Category: suggestion_pattern[x].1, x: formatDate(offset: Double(x)*5.0*60.0), y: Double(suggestion_pattern[x].0))
                }


            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
