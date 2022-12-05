//
//  PromptView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

struct PromptView: View {
    @Binding var prompt: GaussPrompt
    @Binding var images: GaussImages
    @Binding var document: GaussDocument
    var selected: Bool = false
    var canGenerate: Bool = true
    var canDelete: Bool = true
    var canDuplicate: Bool = true
    @State private var batchSize = 1
    @State private var jobs: [GenerateImageJob] = []
    @EnvironmentObject private var kernel: GaussKernel
    @FocusState private var focused
    
    var locked: Bool {
        return prompt.results.count > 0 || jobs.count > 0
    }
    
    var hasResults: Bool {
        return (jobs.count + prompt.results.count) > 0
    }
        
    var shouldFocusOnReveal: Bool {
        let newestPrompt = document.prompts.max(by: { $0.createdAt < $1.createdAt })
        return newestPrompt?.id == prompt.id
    }
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                card.padding()
            }
            if hasResults {
                results
            }
        }
    }
    
    var card: some View {
        Group {
        VStack {
            /// Section for editing the prompt
            Group {
                HStack(spacing: 20) {
                    promptTextField.disabled(locked)
                    if canDelete {
                        deleteButton
                    }
                }.padding([.horizontal, .top])
                
                Group {
                    HStack(spacing: 20) {
                        stepsSlider
                        Toggle("Safe", isOn: $prompt.safety)
                            .toggleStyle(.switch)
                            .help(Text("If enabled, try to hide images that contain unsafe content. Often removes progress results."))
                    }.padding(.horizontal)
                    
                    HStack(spacing: 20) {
                        guidanceSlider
                        modelPicker
                    }.padding(.horizontal)
                }.disabled(locked)
            }
            
            /// Section for generating & reviewing images
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 0) {
                    if canGenerate {
                        BottomBarButtonLabel {
                            HStack {
                                Text("Generate")
                                Button("1") {
                                    generateImage(1)
                                }
                                Button("4") {
                                    generateImage(4)
                                }
                                Button("9") {
                                    generateImage(9)
                                }
                            }
                        }
                    }
                    
                    if canGenerate && canDuplicate {
                        Divider()
                    }
                    
                    if canDuplicate {
                        Button {
                            self.copyPrompt()
                        } label: {
                            BottomBarButtonLabel {
                                Text("Duplicate")
                            }
                        }
                    }

                    
                }.fixedSize(horizontal: false, vertical: true)
                    .buttonStyle(.borderless)
                Divider().opacity(0)
                
                
                if (hasResults) {
                }
            }
        }
        }.background(background).frame(maxWidth: 600)
    }
    
    var promptTextField: some View {
        TextField(
            "Prompt",
            text: $prompt.text,
            axis: .vertical
        )
        .onSubmit {
            generateImage(1)
        }
        .focused($focused)
        .task {
            if shouldFocusOnReveal {
                self.focused = true
            }
        }
        .textFieldStyle(.plain)
        .font(Font.headline)
        .navigationTitle("Prompt")
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var stepsSlider: some View {
        Slider(value: $prompt.steps, in: 1...75, step: 5) {
        } minimumValueLabel: {
            Text("Speed")
        } maximumValueLabel: {
            Text("Quality")
        }.help(Text("Number of diffusion steps to perform"))
    }
    
    var guidanceSlider: some View {
        Slider(value: $prompt.guidance, in: 0...20) {
        } minimumValueLabel: {
            Text("Creative")
        } maximumValueLabel: {
            Text("Predictable")
        }.help(Text("Guidance factor; set to zero for random output"))
    }
    
    var modelPicker: some View {
        Picker("Model", selection: $prompt.model) {
            Text("SD 2.0").tag(GaussModel.sd2).help(Text("Stable Diffusion 2.0 Base"))
            Text("SD 1.5").tag(GaussModel.sd1_5).help(Text("Stable Diffusion 1.5"))
            Text("SD 1.4").tag(GaussModel.sd1_4).help(Text("Stable Diffusion 1.4"))
            // TODO: support custom models
        }
        .fixedSize()
            .onChange(of: prompt.model) { model in
                kernel.preloadPipeline(prompt.model)
            }
    }
    
    var results: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 1) {
                    ForEach($prompt.results) { $result in
                        ResultView(result: $result, images: $images).onAppear {
//                            scroller.scrollTo(result.id)
                        }.id(result.id)
                    }
                    
                    ForEach($jobs) { $job in
                        GaussProgressView(job: job).onAppear {
//                            scroller.scrollTo(job.id)
                        }.id(job.id)
                    }
                }
            }
        }
    }
    
    var deleteButton: some View {
        Button {
            self.delete()
        } label: {
            Image(systemName: "xmark")
        }.help(Text("Delete prompt and results"))
            .buttonStyle(.borderless)
            .contentShape(Circle())
    }

    
    var background: some View {
        let rect = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let stroke = rect.strokeBorder(.separator)
        let selectedStroke = rect.strokeBorder(.blue, lineWidth: 2)
        let background = rect
            .fill(Color(nsColor: NSColor.windowBackgroundColor))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        return background.overlay(selected || focused ? AnyView(selectedStroke) : AnyView(stroke))
    }
    
    func generateImage(_ count: Int) {
        let willBecomeLocked = !locked
        let job = kernel.startGenerateImageJob(forPrompt: prompt, count: count) { results, job in
            saveResults(results)
            jobs.removeAll(where: { $0.id == job.id })
            kernel.jobs.removeValue(forKey: job.id)
        }
        withAnimation(.default) {
            jobs.append(job)
            if willBecomeLocked {
                copyPrompt()
            }
        }
    }
    
    func copyPrompt() {
        var copy = self.prompt
        let defaults = GaussPrompt()
        
        copy.id = defaults.id
        copy.createdAt = defaults.createdAt
        copy.results = defaults.results
        copy.favorite = defaults.favorite
        copy.hidden = defaults.hidden
        
        let position = self.document.prompts.firstIndex(where: { $0.id == self.prompt.id })
        withAnimation(.default) {
            self.document.prompts.insert(copy, at: (position ?? 0) + 1)
        }
    }
    
    func saveResults(_ images: [CGImage?]) {
        var ids: [UUID] = []
        for image in images {
            let id = UUID()
            ids.append(id)
            guard let nsImage = image?.asNSImage() else {
                continue
            }
            self.images[id.uuidString] = nsImage
        }
        let result = GaussResult(promptId: prompt.id, imageIds: ids)
        prompt.results.append(result)
    }
    
    func delete() {
        if (document.prompts.count == 1) {
            document.prompts.append(GaussPrompt())
        }
        
        let ownPrompt = self.prompt
        document.prompts.removeAll(where: { $0.id == ownPrompt.id })
        for result in ownPrompt.results {
            for imageId in result.imageIds {
                document.images.removeValue(forKey: imageId.uuidString)
            }
        }
    }
}

struct PromptView_Previews: PreviewProvider {
    @State static var doc = GaussDocument(prompts: [
        GaussPrompt()
    ])
    @State static var prompt = doc.prompts.first!
    
    static var previews: some View {
        PromptView(prompt: $prompt, images: .constant([:]), document: $doc).padding()
        
    }
}

struct BottomBarButtonLabel<Content: View>: View {
    var content: () -> Content
    
    var body: some View {
        VStack{
            Divider().opacity(0)
            HStack(spacing: 0) {
                Spacer()
                content()
                Spacer()
                    
            }
            Divider().opacity(0)
        }.contentShape(Rectangle())
    }
}