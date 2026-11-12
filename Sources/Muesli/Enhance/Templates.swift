import Foundation
import SwiftUI

struct TemplateSection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var hint: String

    init(id: UUID = UUID(), title: String, hint: String) {
        self.id = id
        self.title = title
        self.hint = hint
    }

    enum CodingKeys: String, CodingKey { case id, title, hint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
    }
}

struct MeetingTemplate: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var description: String
    var promptHint: String
    var sections: [TemplateSection]
    var isBuiltin: Bool

    init(id: String, name: String, description: String = "", promptHint: String = "", sections: [TemplateSection] = [], isBuiltin: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.promptHint = promptHint
        self.sections = sections
        self.isBuiltin = isBuiltin
    }

    var promptBlock: String {
        if !sections.isEmpty {
            return sections.map { "- \($0.title): \($0.hint)" }.joined(separator: "\n")
        }
        return promptHint
    }

    static let builtin: [MeetingTemplate] = [
        MeetingTemplate(
            id: "auto",
            name: "Padrão Executivo",
            description: "Estrutura equilibrada para reuniões em geral.",
            promptHint: "Resumo Executivo, Deliberações e Discussão Técnica, Decisões Tomadas e Plano de Ação.",
            sections: [
                TemplateSection(title: "Resumo Executivo", hint: "Visão geral objetiva de três a cinco frases sobre o objetivo e o andamento da reunião."),
                TemplateSection(title: "Deliberações e Discussão Técnica", hint: "Principais pontos discutidos agrupados por tópico com contexto técnico e status."),
                TemplateSection(title: "Decisões Tomadas", hint: "Tudo o que foi acordado ou definido pelos participantes."),
                TemplateSection(title: "Plano de Ação", hint: "Tabela ou lista de tarefas com responsável e prazo/momento acordados."),
            ],
            isBuiltin: true
        ),
        MeetingTemplate(
            id: "one_on_one",
            name: "1:1 / Alinhamento Individual",
            description: "Check-in pessoal e alinhamento individual entre duas pessoas.",
            sections: [
                TemplateSection(title: "Como as coisas estão", hint: "Clima, vitórias e atualizações gerais."),
                TemplateSection(title: "Tópicos Discutidos", hint: "Principais temas levantados."),
                TemplateSection(title: "Feedbacks", hint: "Feedbacks compartilhados em ambas as direções."),
                TemplateSection(title: "Ações e Compromissos", hint: "Compromissos firmados com prazos."),
            ],
            isBuiltin: true
        ),
        MeetingTemplate(
            id: "standup",
            name: "Daily / Standup",
            description: "Sincronização diária de equipe.",
            sections: [
                TemplateSection(title: "Concluído", hint: "O que foi finalizado desde o último encontro por pessoa."),
                TemplateSection(title: "Em andamento", hint: "O que está sendo feito no momento."),
                TemplateSection(title: "Impedimentos", hint: "Bloqueios ou necessidades de ajuda."),
                TemplateSection(title: "Ações do dia", hint: "Próximos passos combinados na daily."),
            ],
            isBuiltin: true
        ),
        MeetingTemplate(
            id: "weekly_sync",
            name: "Alinhamento Semanal",
            description: "Alinhamento semanal de time ou projeto.",
            sections: [
                TemplateSection(title: "Resumo da Semana", hint: "Panorama geral do progresso e prioridades."),
                TemplateSection(title: "Atualizações por Projeto", hint: "Status e entregas de cada frente."),
                TemplateSection(title: "Riscos e Pontos de Atenção", hint: "Itens atrasados, gargalos ou preocupações."),
                TemplateSection(title: "Decisões", hint: "Deliberações e caminhos escolhidos."),
                TemplateSection(title: "Plano de Ação", hint: "Tarefas, responsáveis e prazos."),
            ],
            isBuiltin: true
        ),
        MeetingTemplate(
            id: "sales_discovery",
            name: "Comercial / Descoberta",
            description: "Reunião de alinhamento com cliente ou prospect.",
            sections: [
                TemplateSection(title: "Contexto e Participantes", hint: "Quem são, cargo e escopo da empresa."),
                TemplateSection(title: "Dores e Necessidades", hint: "Problemas descritos e objetivos buscados."),
                TemplateSection(title: "Cenário Atual", hint: "Processos, sistemas e ferramentas atuais."),
                TemplateSection(title: "Orçamento e Cronograma", hint: "Expectativas de prazo, orçamento e decisão."),
                TemplateSection(title: "Próximos Passos", hint: "Ações combinadas de acompanhamento."),
            ],
            isBuiltin: true
        ),
        MeetingTemplate(
            id: "interview",
            name: "Entrevista",
            description: "Avaliação e alinhamento de candidatos.",
            sections: [
                TemplateSection(title: "Perfil e Trajetória", hint: "Experiência anterior e pontos fortes citados."),
                TemplateSection(title: "Perguntas e Respostas Chave", hint: "Perguntas centrais e como o candidato respondeu."),
                TemplateSection(title: "Pontos Fortes", hint: "Destaques positivos."),
                TemplateSection(title: "Pontos de Atenção", hint: "Possíveis gaps técnicos ou culturais."),
                TemplateSection(title: "Próximos Passos", hint: "Ações no processo seletivo."),
            ],
            isBuiltin: true
        ),
    ]

    @MainActor
    static var all: [MeetingTemplate] {
        builtin + TemplateStore.shared.customTemplates
    }

    @MainActor
    static func find(_ id: String) -> MeetingTemplate {
        all.first { $0.id == id } ?? builtin[0]
    }
}

@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published private(set) var customTemplates: [MeetingTemplate] = []
    private let fileURL: URL

    private init() {
        self.fileURL = MeetingStore.defaultBaseDir().appendingPathComponent("templates.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([MeetingTemplate].self, from: data)
        else { return }
        customTemplates = list
    }

    func saveCustom(_ template: MeetingTemplate) {
        var copy = template
        copy.isBuiltin = false
        if let idx = customTemplates.firstIndex(where: { $0.id == copy.id }) {
            customTemplates[idx] = copy
        } else {
            customTemplates.append(copy)
        }
        persist()
    }

    func deleteCustom(id: String) {
        customTemplates.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(customTemplates) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
