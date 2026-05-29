# frozen_string_literal: true

require "rails_helper"
require "decidim/accountability/test/factories"

describe "Admin edits accountability results with legacy remote images", type: :system, js: true do
  let(:organization) do
    create(
      :organization,
      default_locale: :ca,
      available_locales: [:ca]
    )
  end

  let(:admin) { create(:user, :admin, :confirmed, organization: organization) }
  let(:participatory_process) { create(:participatory_process, :with_steps, organization: organization) }
  let(:component) { create(:accountability_component, participatory_space: participatory_process) }
  let(:result_status) { create(:status, component: component, name: { ca: "En curs" }) }

  let(:description_html) do
    <<~HTML.gsub(/\n\s*/, "")
      <ul><li><strong>Descripció</strong>:&nbsp;Posar nous elements de joc infanttil i una prègola vegetal a l’espai que hi ha a tocar del passeig del Roser.</li><li><strong>Ubicació</strong>:&nbsp;Casal Mira-sol</li><li><strong>Pressupost</strong>:&nbsp;25.000 euros.</li><li><strong>Objectiu</strong>: Millorar l’oferta de jocs infantils a l’exterior del Casal.</li></ul><p><img border="0" data-original-height="1200" data-original-width="1600" src="https://1.bp.blogspot.com/-3k1rWVNVEWI/XeZXYB_xAaI/AAAAAAAAC9g/uIkHBypXIsEybZKwMF2BfnRMy9iqsnO9wCLcBGAsYHQ/s1600/WhatsApp%2BImage%2B2019-12-03%2Bat%2B11.56.57.jpeg"></p><p><strong>3 de desembre del 2019. Projecte executat:</strong></p><p>A principis de desembre, ja hi ha la pèrgola vegetal i tots els jocs instal·lats i a punt per utilitzar. Només falta acabar de relligar les branques de la pèrgola.</p><p><img border="0" data-original-height="900" data-original-width="1600" src="https://1.bp.blogspot.com/-k3xm0TEYUdE/XeZT34NgETI/AAAAAAAAC9A/ET2WonxjTgMGbmPSV932qEa5MXRaN82VgCLcBGAsYHQ/s1600/20191203_103036.jpg"></p><p><img border="0" data-original-height="900" data-original-width="1600" src="https://1.bp.blogspot.com/-dkdrJn-TlCA/XeZTyQzyn2I/AAAAAAAAC84/qqBpYeEUFt48oAuzdDxBXzir-a31uQvWACLcBGAsYHQ/s1600/20191203_103006.jpg"></p><p><strong>18 de novembre del 2019. Comencen els treballs</strong>:</p><p>A mitjans de novembre, comencen les obres per instal·lar els nous elements de joc a tocar de la nova pèrgola vegetal. Els trreballs s'allarguen fins a finals de mes.</p><p><img border="0" data-original-height="900" data-original-width="1600" src="https://1.bp.blogspot.com/-iVB9lqOG-Us/XeZTmNczCMI/AAAAAAAAC8w/4LeVPadJIwwLZWWFzeb_q-3m3ndu1Q-qACLcBGAsYHQ/s1600/20191127_093259.jpg"></p><p><img border="0" data-original-height="900" data-original-width="1600" src="https://1.bp.blogspot.com/-tVl042DWHW8/XeZTeIgu02I/AAAAAAAAC8s/kOXjh9m2_i4u61cQSDag2QnAXmQTLptIACLcBGAsYHQ/s1600/20191126_101833.jpg"></p><p><strong>Maig de 2019. S'acaba de definir el projecte:</strong></p><p>Es proposa posar més elements de joc infantil a la zona que hi ha a tocar del passeig del Roser. Concretament, el projecte preveu instal·lar:</p><ul><li>Un gronxador de cistella.</li><li>Dos elements de molles.</li><li>Un element giratori.</li><li>Bancs per seure</li><li>Jocs d’equilibri fets amb troncs.</li><li>Ampliar el sorral actual i cobrir-lo amb una pèrgola vegetal que garanteixi que l'espai tingui ombra.</li></ul><p><img border="0" data-original-height="1324" data-original-width="1600" src="https://1.bp.blogspot.com/-bMdtxWww4YM/XdKH73biltI/AAAAAAAAC18/07EtiBMp_4I60zrgH_Fxf7WFck3g_BAZgCLcBGAsYHQ/s1600/CASAL_planta%2Bjocs.jpg"></p><p><img border="0" data-original-height="898" data-original-width="1600" src="https://1.bp.blogspot.com/-4J1e_m0Hj28/XeZTCXQYL_I/AAAAAAAAC8k/6O0e3qDxhmQ7XOoVDea95p1KZZzb4q_DgCLcBGAsYHQ/s1600/1.JPG"></p>
    HTML
  end

  let!(:result) do
    create(
      :result,
      component: component,
      status: result_status,
      title: { ca: "Jocs infantils Casal Mira-sol" },
      description: { ca: description_html }
    )
  end

  let(:expected_image_sources) do
    Nokogiri::HTML::DocumentFragment.parse(description_html).css("img[src]").map { |image| image["src"] }
  end

  let(:component_admin_path) do
    Decidim::EngineRouter.admin_proxy(component).root_path
  end

  let(:description_editor_selector) { "#result_description_ca" }

  before do
    switch_to_host(organization.host)
    login_as admin, scope: :user
  end

  it "rehydrates all legacy remote images in the editor" do
    visit component_admin_path

    within "tr[data-id='#{result.id}'] .table-list__actions" do
      find("a.action-icon--edit").click
    end

    within description_editor_selector do
      expect(page).to have_css(".editor-input .ProseMirror")
      expect(page).to have_css(".editor-input .ProseMirror img[src]", count: expected_image_sources.count)
    end

    expect(editor_image_sources).to eq(expected_image_sources)
  end

  def editor_image_sources
    page.evaluate_script(<<~JS)
      Array.from(
        document.querySelectorAll("#{description_editor_selector} .editor-input .ProseMirror img[src]")
      ).map((image) => image.getAttribute("src"))
    JS
  end
end
